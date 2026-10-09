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
  // Rust module initialization precedes async Profile load. Wait for actual
  // validated editor / Board controls, not merely a loaded Wasm module.
  await page.waitForFunction(() =>
    document.querySelector('#layer-picker')?.value === 'layer.ja'
    && document.querySelector('#board-picker')?.value === 'board.ja.root'
    && !document.querySelector('#board-picker')?.disabled,
    null, {timeout: 25000});

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
  // M3f: the current authored default transition is shown without any JS
  // semantic editing. Only the canonical Rust command updates its meaning.
  const target = page.locator('#entry-transition-board');
  const lifetime = page.locator('#entry-transition-lifetime');
  assert.equal(await target.inputValue(), 'board.base.kana.a.flick');
  assert.equal(await lifetime.inputValue(), 'transient');
  const initialGuides = await kana.locator('.flick-guide').allTextContents();
  await target.selectOption('board.base.kana.ka.flick');
  await lifetime.selectOption('persistent');
  await page.locator('#apply-entry-transition').click();
  assert.equal(await target.inputValue(), 'board.base.kana.ka.flick');
  assert.equal(await lifetime.inputValue(), 'persistent');
  assert.ok((await page.locator('#save-info').innerText()).includes('未保存の編集'));
  const changedGuides = await kana.locator('.flick-guide').allTextContents();
  assert.notDeepStrictEqual(changedGuides, initialGuides, 'Rust preview guides must follow the selected transition');

  await page.locator('#undo-edit').click();
  assert.equal(await target.inputValue(), 'board.base.kana.a.flick');
  assert.equal(await lifetime.inputValue(), 'transient');
  assert.deepStrictEqual(await kana.locator('.flick-guide').allTextContents(), initialGuides);
  await page.locator('#redo-edit').click();
  assert.equal(await target.inputValue(), 'board.base.kana.ka.flick');
  assert.equal(await lifetime.inputValue(), 'persistent');

  await target.selectOption('');
  assert.equal(await lifetime.isDisabled(), true);
  await page.locator('#apply-entry-transition').click();
  assert.equal(await target.inputValue(), '');
  // Deliberately send an impossible Board ID through the UI; Rust must
  // reject the change atomically and preserve the actual source document.
  await target.evaluate(el => {
    const missing = document.createElement('option');
    missing.value = 'board.absent';
    missing.textContent = 'invalid fixture';
    el.append(missing);
    el.value = missing.value;
    el.dispatchEvent(new Event('change', {bubbles: true}));
  });
  await page.locator('#apply-entry-transition').click();
  await page.waitForFunction(() => document.querySelector('#status')?.textContent?.includes('遷移変更失敗'));
  await kana.click();
  assert.equal(await target.inputValue(), '', 'invalid target must not mutate the Profile');
  await page.locator('#undo-edit').click();
  await page.locator('#undo-edit').click();
  assert.equal(await target.inputValue(), 'board.base.kana.a.flick');
  assert.equal(await lifetime.inputValue(), 'transient');

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

  // M3h: real mobile Chromium/Wasm, Rust is the Macro ID/name/action owner.
  assert.equal(await page.locator('#macro-select option').count(), 0);
  await page.locator('#macro-create-sample').click();
  assert.equal(await page.locator('#macro-select option').count(), 1);
  assert.ok((await page.locator('#macro-selected-meta').innerText()).includes('macro.user.'));
  assert.equal(await page.locator('#macro-name').inputValue(), 'サンプル：あいさつ');
  assert.ok((await page.locator('#macro-actions option').first().innerText()).includes('こんにちは！'));
  await page.locator('#macro-action-text').fill('マクロの動作確認');
  await page.locator('#macro-edit-action').click();
  assert.ok((await page.locator('#macro-actions option').first().innerText()).includes('マクロの動作確認'));
  await page.locator('#macro-name').fill('共有マクロ');
  await page.locator('#macro-rename').click();
  assert.equal(await page.locator('#macro-name').inputValue(), '共有マクロ');
  await page.locator('#undo-edit').click();
  assert.equal(await page.locator('#macro-name').inputValue(), 'サンプル：あいさつ');
  await page.locator('#redo-edit').click();
  assert.equal(await page.locator('#macro-name').inputValue(), '共有マクロ');
  await page.locator('#macro-create-name').fill('  共有マクロ  ');
  await page.locator('#macro-create').click();
  assert.ok((await page.locator('#status').innerText()).includes('Macro作成失敗'));
  assert.equal(await page.locator('#macro-select option').count(), 1, 'duplicate name must be rejected atomically');
  await page.locator('#macro-new-action').click();
  await page.locator('#macro-action-type').selectOption('noop');
  await page.locator('#macro-add-action').click();
  assert.equal(await page.locator('#macro-actions option').count(), 2);
  assert.ok((await page.locator('#macro-actions option').last().innerText()).includes('何もしない'));
  console.log('M3h Macro create/rename/duplicate reject/action-edit/Undo/Redo via canonical Rust PASS');

  await page.locator('#save-local').click();
  await page.waitForFunction(() => document.querySelector('#save-info')?.textContent?.includes('ブラウザに保存済'));
  assert.ok((await page.locator('#save-info').innerText()).includes('未反映'));

  await page.reload({waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('#rust-status')?.textContent === 'Rust稼働中', null, {timeout: 25000});
  await page.locator('button.key[data-entry-id="kana.a"]').waitFor();
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), '共通Web編集');
  assert.ok((await page.locator('#profile-name').innerText()).includes('Web動作確認'));
  assert.equal(await page.locator('#macro-name').inputValue(), '共有マクロ');
  assert.equal(await page.locator('#macro-actions option').count(), 2);
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
  // A valid existing advanced Macro action remains intact, not silently normalized away.
  custom.macros = [{
    id: 'macro.opaque', name: '既存アクション保持',
    actions: [{actionID: 'system.dismissKeyboard', arguments: {}}]
  }];
  await page.locator('#profile-file').setInputFiles({
    name: 'custom-profile.json', mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(custom), 'utf8'),
  });
  await page.waitForFunction(() => document.querySelector('#profile-name')?.textContent?.includes('外部Profile復元テスト'));
  assert.equal(await page.locator('#macro-select option').count(), 1);
  await page.locator('#macro-actions').selectOption('0');
  assert.equal(await page.locator('#macro-edit-action').isDisabled(), true);
  assert.ok((await page.locator('#macro-action-hint').innerText()).includes('読み取り専用'));
  await page.locator('#macro-new-action').click();
  await page.locator('#macro-action-type').selectOption('noop');
  await page.locator('#macro-add-action').click();
  assert.equal(await page.locator('#macro-actions option').count(), 2);
  assert.ok((await page.locator('#macro-actions option').first().innerText()).includes('system.dismissKeyboard'));
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
      document.querySelector('#rust-status')?.textContent === 'Rust稼働中'
      && document.querySelector('#profile-name')?.textContent?.includes('外部Profile復元テスト')
      && document.querySelector('#save-info')?.textContent?.includes('ブラウザに保存済'),
      null, {timeout: 20000});
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
