import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {join} from 'node:path';

const browser = await chromium.launch({headless: true, args: ['--no-sandbox']});
const errors = [];
try {
  const context = await browser.newContext({
    viewport: {width: 390, height: 844},
    isMobile: true, hasTouch: true, deviceScaleFactor: 2,
    acceptDownloads: true,
  });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(String(error)));
  await page.goto('http://127.0.0.1:8765/', {waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('#rust-status')?.textContent === 'Rust稼働中', null, {timeout: 25000});

  assert.equal(await page.locator('#layer-picker').inputValue(), 'layer.ja');
  assert.equal(await page.locator('#board-picker').inputValue(), 'board.ja.root');
  await page.locator('#board-picker').selectOption('board.base.kana.a.flick');
  await page.waitForFunction(() => document.querySelector('#board-preview-state')?.dataset.mode === 'edit');
  const internal = page.locator('#board button.key').first();
  await internal.waitFor({state: 'visible'});
  await internal.click();
  const internalOriginal = (await internal.locator('.key-label').innerText()).trim();
  await page.locator('#entry-text').fill('内部Board編集確認');
  await page.locator('#apply-key-text').click();
  assert.equal((await page.locator('#board button.key').first().locator('.key-label').innerText()).trim(), '内部Board編集確認');
  assert.equal(await page.locator('#board-picker').inputValue(), 'board.base.kana.a.flick');
  await page.locator('#undo-edit').click();
  assert.equal((await page.locator('#board button.key').first().locator('.key-label').innerText()).trim(), internalOriginal);
  await page.locator('#redo-edit').click();
  assert.equal((await page.locator('#board button.key').first().locator('.key-label').innerText()).trim(), '内部Board編集確認');
  await page.locator('#undo-edit').click();
  // Internal Board selection is an edit-only preview, not a false Stage replay.
  assert.ok((await page.locator('#board-preview-state').innerText()).includes('編集専用'));
  await page.locator('#board-picker').selectOption('board.ja.root');
  await page.waitForFunction(() => document.querySelector('#board-preview-state')?.dataset.mode === 'replay');
  assert.equal(await page.locator('#board-picker').inputValue(), 'board.ja.root');

  const kana = page.locator('button.key[data-entry-id="kana.a"]');
  await kana.waitFor({state: 'visible'});
  const nativeGuides = kana.locator('.flick-guide');
  assert.ok(await nativeGuides.count() >= 4, 'Rust preview must expose immediate kana flick labels');
  const labels = await nativeGuides.allTextContents();
  assert.ok(labels.some(x => x.trim().length > 0));
  assert.ok((await kana.getAttribute('aria-label')).includes('フリック候補'));
  assert.ok((await page.locator('#save-info').innerText()).includes('未変更'));
  await kana.click();
  const original = (await kana.locator('.key-label').innerText()).trim();
  assert.ok(original);
  assert.equal(await page.locator('#apply-key-text').isEnabled(), true);

  await page.locator('#entry-text').fill('共通Web編集');
  await page.locator('#apply-key-text').click();
  assert.ok((await page.locator('#save-info').innerText()).includes('未保存の編集'));
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), '共通Web編集');
  assert.ok(await page.locator('button.key[data-entry-id="kana.a"] .flick-guide').count() >= 4,
    'editing default text must not discard Rust flick guides');
  assert.equal(await page.locator('#undo-edit').isEnabled(), true);

  await page.locator('#undo-edit').click();
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), original);
  await page.locator('#redo-edit').click();
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), '共通Web編集');

  await page.locator('#profile-title').fill('Web動作確認');
  await page.locator('#rename-profile').click();
  assert.ok((await page.locator('#profile-name').innerText()).includes('Web動作確認'));

  await page.locator('#save-local').click();
  await page.waitForFunction(() => document.querySelector('#save-info')?.textContent?.includes('ブラウザに保存済'));
  assert.ok((await page.locator('#save-info').innerText()).includes('未反映'));

  await page.reload({waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('#rust-status')?.textContent === 'Rust稼働中', null, {timeout: 25000});
  await page.locator('button.key[data-entry-id="kana.a"]').waitFor();
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), '共通Web編集');
  assert.ok((await page.locator('#profile-name').innerText()).includes('Web動作確認'));
  assert.ok((await page.locator('#save-info').innerText()).includes('ブラウザに保存済'));

  await page.locator('button.key[data-entry-id="kana.a"]').click();
  await page.waitForFunction(() => document.querySelector('#status')?.textContent?.includes('Rust判定を実行'));
  assert.ok((await page.locator('#trace-state').innerText()).includes('Committed'));

  await page.locator('#profile-file').setInputFiles({
    name: 'invalid.json', mimeType: 'application/json',
    buffer: Buffer.from('{', 'utf8'),
  });
  await page.waitForFunction(() => document.querySelector('#status')?.textContent?.includes('Profileが無効'));
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), '共通Web編集');

  // A different locally imported Profile must also restore on restart.
  // This catches boot paths which unconditionally reopen only builtin.ja.product.
  const custom = await page.evaluate(async () => (await (await fetch('./default-ja.json')).json()));
  custom.id = 'user.web.persisted';
  custom.name = '外部Profile復元テスト';
  await page.locator('#profile-file').setInputFiles({
    name: 'custom-profile.json', mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(custom), 'utf8'),
  });
  await page.waitForFunction(() => document.querySelector('#profile-name')?.textContent?.includes('外部Profile復元テスト'));
  await page.locator('#save-local').click();
  await page.waitForFunction(() => document.querySelector('#save-info')?.textContent?.includes('ブラウザに保存済'));
  await page.reload({waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('#rust-status')?.textContent === 'Rust稼働中');
  await page.waitForFunction(() => document.querySelector('#profile-name')?.textContent?.includes('外部Profile復元テスト'));
  assert.ok((await page.locator('#save-info').innerText()).includes('ブラウザに保存済'));
  // Offline W4: use installed service-worker cache, not browser HTTP/network.
  // Browser-only acceptance; real iPhone Safari/A2HS remains device-gated.
  await page.evaluate(async () => {
    const reg = await navigator.serviceWorker.ready;
    if (!reg.active) throw new Error('PWA service worker did not activate');
  });
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, {timeout: 20000});
  await context.setOffline(true);
  try {
    await page.reload({waitUntil: 'domcontentloaded'});
    await page.waitForFunction(() =>
      document.querySelector('#rust-status')?.textContent === 'Rust稼働中', null, {timeout: 20000});
    assert.ok((await page.locator('#profile-name').innerText()).includes('外部Profile復元テスト'),
      'Offline launch must restore local imported Profile, not reset to builtin');
    assert.ok((await page.locator('#save-info').innerText()).includes('ブラウザに保存済'));
    assert.ok(await page.locator('button.key[data-entry-id="kana.a"] .flick-guide').count() >= 4,
      'Offline runtime must still expose canonical Rust flick guides');
    await page.locator('button.key[data-entry-id="kana.a"]').click();
    await page.waitForFunction(() =>
      document.querySelector('#status')?.textContent?.includes('Rust判定を実行'), null, {timeout: 15000});
    const sample = await page.evaluate(async () => {
      const r = await fetch('./default-ja.json');
      if (!r.ok) throw new Error('Cached public default-ja.json response failed: ' + r.status);
      return (await r.json()).schema;
    });
    assert.equal(sample, 'gesture-ime.profile.v3');
    console.log('W4 browser OFFLINE service-worker Wasm boot + local Profile recovery + Rust flick trace PASS');
  } finally {
    await context.setOffline(false);
  }
  if (errors.length) throw new Error('browser pageerror: ' + errors.join('; '));

  await page.screenshot({path: join(process.env.RUNNER_TEMP || '.', 'gesture-ime-mobile-smoke.png'), fullPage: true});
  console.log('M3b browser Rust/Wasm editor → Undo/Redo → IndexedDB save → reload → gesture + invalid file PASS');
  await context.close();
} finally {
  await browser.close();
}
