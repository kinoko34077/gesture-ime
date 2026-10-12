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

  // Real end-user first view: immediately usable test, not long edit forms.
  assert.equal(await page.locator('#app').getAttribute('data-workspace'), 'test');
  assert.equal(await page.locator('#mode-test').getAttribute('aria-pressed'), 'true');
  assert.equal(await page.locator('.inspector-pane').isVisible(), false);
  assert.equal(await page.locator('#layer-picker').isVisible(), false);
  assert.equal(await page.locator('#test-output').isVisible(), true);
  assert.ok((await page.locator('#try-instructions').innerText()).includes('タップ'));
  const firstViewport = await page.locator('#board').boundingBox();
  assert.ok(firstViewport.y < 560, 'test keyboard should be inside the first phone viewport');
  await page.locator('button.key[data-entry-id="kana.a"]').click();
  assert.equal((await page.locator('#test-output').innerText()).trim(), 'あ');
  await page.locator('.test-layer-choice[data-layer-id="layer.alpha"]').click();
  assert.equal(await page.locator('#board-picker').inputValue(), 'board.alpha.root');
  assert.equal(await page.locator('#board-preview-state').getAttribute('data-mode'), 'replay');
  await page.locator('button.key[data-entry-id="alpha.abc"]').click();
  assert.ok((await page.locator('#test-output').innerText()).trim().length > 1,
    'Rust replay from Latin Layer must add a dispatched text action');
  await page.locator('.test-layer-choice[data-layer-id="layer.numbers"]').click();
  assert.equal(await page.locator('#board-preview-state').getAttribute('data-mode'), 'replay');
  await page.locator('button.key[data-entry-id="num.1"]').click();
  assert.ok((await page.locator('#test-output').innerText()).includes('1'),
    'number Layer must be actually judged by Rust and append the number');
  await page.locator('#clear-test-output').click();
  assert.equal(await page.locator('#test-output').getAttribute('data-empty'), 'true');
  await page.locator('#mode-edit').click();
  assert.equal(await page.locator('#app').getAttribute('data-workspace'), 'edit');
  assert.equal(await page.locator('.inspector-pane').isVisible(), true);
  assert.equal(await page.locator('#layer-picker').isVisible(), true);
  await page.locator('#layer-picker').selectOption('layer.ja');
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
  assert.ok((await page.locator('#gesture-result').innerText()).includes('Rust判定：'),
    'visible keyboard-adjacent feedback must report canonical Rust result on release');
  assert.equal(await page.locator('#trace-details').evaluate(el => el.open), false,
    'verbose trace stays collapsed by default rather than pushing keyboard feedback away');
  const feedbackNearBoard = await page.locator('#gesture-feedback').evaluate(el =>
    !!(el.compareDocumentPosition(document.querySelector('#board')) & Node.DOCUMENT_POSITION_PRECEDING));
  assert.ok(feedbackNearBoard, 'Rust result must immediately follow the keyboard, not be below editing forms');
  await kana.scrollIntoViewIfNeeded();
  const keyBox = await kana.boundingBox();
  const boardBeforePress = await page.locator('#board').boundingBox();
  await page.mouse.move(keyBox.x + keyBox.width / 2, keyBox.y + keyBox.height / 2);
  await page.mouse.down();
  assert.ok((await page.locator('#gesture-result').innerText()).includes('指を離した後'));
  assert.ok(Math.abs((await page.locator('#board').boundingBox()).y - boardBeforePress.y) <= 1,
    'opening flick hints must not shift the keyboard away from the pressed finger');
  assert.equal(await page.locator('#gesture-guides').evaluate(el => getComputedStyle(el).position), 'absolute',
    'duplicated text guide stays accessible without adding a layout row');
  assert.ok((await page.locator('#gesture-guides').innerText()).includes('い'),
    'Rust-projected left flick output must appear beside active keyboard');
  assert.ok(await page.locator('#gesture-guides .gesture-guide-item').count() >= 4);
  // The popup uses this key's exact Rust-projected cardinal guides, not a
  // hardcoded kana/English table or a JS directional hit engine.
  const popup = page.locator('#flick-popup');
  assert.equal(await popup.count(), 1);
  assert.equal(await popup.getAttribute('data-source-entry-id'), 'kana.a');
  assert.equal((await popup.locator('[data-direction="west"]').innerText()).trim(), 'い');
  assert.equal((await popup.locator('[data-direction="center"]').innerText()).trim(), 'あ');
  assert.equal(await popup.locator('.flick-popup-cell:not(.is-center):not(.is-empty)').count(), 4);
  assert.equal(await popup.locator('[data-direction="northWest"].is-empty').count(), 1,
    'unconfigured diagonal must not be presented as a runtime candidate');
  assert.equal(await popup.evaluate(el => getComputedStyle(el).pointerEvents), 'none',
    'overlay must never swallow pointer input intended for the key');
  const overlayBounds = await popup.evaluate(el => {
    const p = el.getBoundingClientRect(), b = document.querySelector('#board').getBoundingClientRect();
    return {left:p.left, right:p.right, boardLeft:b.left, boardRight:b.right};
  });
  assert.ok(overlayBounds.left >= overlayBounds.boardLeft - 2
    && overlayBounds.right <= overlayBounds.boardRight + 2,
    'popup must be fully within keyboard width even at an edge key');
  await page.screenshot({path: join(process.env.RUNNER_TEMP || '.', 'flick-popup-mobile-390.png')});
  await page.mouse.move(keyBox.x + keyBox.width / 2 + 48, keyBox.y + keyBox.height / 2, {steps: 4});
  assert.equal(await popup.count(), 1, 'visual guide remains visible during movement');
  await page.mouse.up();
  assert.equal(await popup.count(), 0, 'popup clears on release');
  assert.ok((await page.locator('#gesture-result').innerText()).includes('Rust判定：'));
  assert.ok((await page.locator('#trace-state').innerText()).includes('Committed'),
    'canonical Rust must still judge the actual flick');

  // Non-kana Layers use the SAME projected popup and now replay canonical
  // Rust sessions from their validated Layer root, not edit-only pretending.
  await page.locator('#layer-picker').selectOption('layer.alpha');
  assert.equal(await page.locator('#board-picker').inputValue(), 'board.alpha.root');
  assert.equal(await page.locator('#board-preview-state').getAttribute('data-mode'), 'replay');
  const latin = page.locator('button.key[data-entry-id="alpha.abc"]');
  await latin.scrollIntoViewIfNeeded();
  const latinBox = await latin.boundingBox();
  await page.mouse.move(latinBox.x + latinBox.width / 2, latinBox.y + latinBox.height / 2);
  await page.mouse.down();
  assert.equal(await popup.getAttribute('data-source-entry-id'), 'alpha.abc');
  assert.ok(await popup.locator('.flick-popup-cell:not(.is-center):not(.is-empty)').count() >= 1,
    'Latin hints also derive from the Rust preview');
  await page.mouse.up();
  assert.ok((await page.locator('#trace-state').innerText()).includes('Committed'),
    'Latin root must commit through canonical Rust rather than remain edit-only');
  assert.equal(await popup.count(), 0);
  await page.locator('#layer-picker').selectOption('layer.ja');
  await kana.click(); // Restore the original key selection for Stage authoring tests.

  // Cancellation must never leave a touch-blocking visual overlay behind.
  await kana.scrollIntoViewIfNeeded();
  const cancelBox = await kana.boundingBox();
  await page.mouse.move(cancelBox.x + cancelBox.width / 2, cancelBox.y + cancelBox.height / 2);
  await page.mouse.down();
  assert.equal(await popup.count(), 1);
  await kana.dispatchEvent('pointercancel', {pointerId: 1, isPrimary: true, bubbles: true});
  assert.equal(await popup.count(), 0);
  await page.mouse.up();

  // Dispatch actual browser touch input (not only a mouse with a mobile viewport).
  // The popup must survive the swipe and leave Rust as the sole release judge.
  await kana.scrollIntoViewIfNeeded();
  const touchBox = await kana.boundingBox();
  const tx = Math.round(touchBox.x + touchBox.width / 2);
  const ty = Math.round(touchBox.y + touchBox.height / 2);
  const cdp = await context.newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', {
    type: 'touchStart', touchPoints: [{x: tx, y: ty, id: 0}]
  });
  assert.equal(await popup.count(), 1, 'real Chromium touchstart reveals key-anchored hint');
  await cdp.send('Input.dispatchTouchEvent', {
    type: 'touchMove', touchPoints: [{x: tx - 48, y: ty, id: 0}]
  });
  assert.equal(await popup.count(), 1, 'real touchmove leaves the popup visible');
  await cdp.send('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []});
  assert.equal(await popup.count(), 0, 'real touchend clears popup');
  assert.ok((await page.locator('#trace-state').innerText()).includes('Committed'),
    'Rust must commit touch flick as well as mouse flick');
  await cdp.detach();
  await page.locator('#trace-details summary').click();
  assert.equal(await page.locator('#trace-details').evaluate(el => el.open), true);
  assert.ok((await page.locator('#trace-actions').innerText()).length > 1);
  await page.locator('#trace-details summary').click();
  const original = (await kana.locator('.key-label').innerText()).trim();
  assert.ok(original);
  // M3l: the selected ordinary key exposes eight virtual directions without
  // creating phantom runtime entries, and nested Stages roundtrip through Rust.
  assert.equal(await page.locator('#stage-grid button[data-direction]').count(), 8);
  const stageNW = page.locator('#stage-grid button[data-direction="northWest"]');
  assert.ok((await stageNW.innerText()).includes('+ 続き'));
  const stageWest = page.locator('#stage-grid button[data-direction="west"]');
  assert.ok((await stageWest.innerText()).includes('い'), 'existing cardinal output remains visible');
  page.once('dialog', async dialog => {
    assert.ok(dialog.message().includes('左'));
    await dialog.dismiss();
  });
  await stageWest.click(); // No consent: the existing cardinal output is not replaced.
  assert.equal(await page.locator('#board-picker').inputValue(), 'board.ja.root');
  await stageNW.click();
  const stageOne = await page.locator('#board-picker').inputValue();
  assert.match(stageOne, /^board\.user\.stage\./);
  assert.ok(await page.locator('#stage-back').isVisible());
  assert.equal(await page.locator('#stage-grid button[data-direction]').count(), 8);
  await page.locator('#stage-grid button[data-direction="northEast"]').click();
  const stageTwo = await page.locator('#board-picker').inputValue();
  assert.match(stageTwo, /^board\.user\.stage\./);
  assert.notEqual(stageTwo, stageOne);
  await page.locator('#stage-back').click();
  assert.equal(await page.locator('#board-picker').inputValue(), stageOne);
  await page.locator('#stage-back').click();
  assert.equal(await page.locator('#board-picker').inputValue(), 'board.ja.root');
  assert.equal((await page.locator('#selected-key').innerText()).trim(), original);
  assert.ok((await page.locator('#stage-grid button[data-direction="northWest"]').innerText()).includes('続きへ'));
  await page.locator('#undo-edit').click();
  await page.locator('#undo-edit').click();
  assert.ok((await page.locator('#stage-grid button[data-direction="northWest"]').innerText()).includes('+ 続き'));
  assert.equal(await page.locator('#board-picker option[value="' + stageOne + '"]').count(), 0);
  assert.equal(await page.locator('#board-picker option[value="' + stageTwo + '"]').count(), 0);
  await page.locator('#redo-edit').click();
  await page.locator('#redo-edit').click();
  assert.equal(await page.locator('#board-picker option[value="' + stageTwo + '"]').count(), 1);
  await page.locator('#undo-edit').click();
  await page.locator('#undo-edit').click();
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
  assert.ok((await page.locator('#entry-transition-feedback').innerText()).includes('遷移先を変更しました'));
  assert.equal(await target.inputValue(), 'board.base.kana.ka.flick');
  assert.equal(await lifetime.inputValue(), 'persistent');
  // An idempotent Rust edit must say "no change", not falsely imply a second commit.
  await page.locator('#apply-entry-transition').click();
  assert.ok((await page.locator('#entry-transition-feedback').innerText()).includes('変更されていません'));
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
  await page.waitForFunction(() => document.querySelector('#entry-transition-feedback')?.textContent?.includes('遷移先を変更できません'));
  assert.equal(await page.locator('#entry-transition-feedback').getAttribute('data-result'), 'error');
  assert.equal(await target.inputValue(), 'board.absent',
    'Rust rejection must leave the attempted target intact for correction');
  await kana.click();
  assert.equal(await target.inputValue(), '', 'invalid target must not mutate the Profile');
  await page.locator('#undo-edit').click();
  await page.locator('#undo-edit').click();
  assert.equal(await target.inputValue(), 'board.base.kana.a.flick');
  assert.equal(await lifetime.inputValue(), 'transient');

  await page.locator('#entry-text').fill('共通Web編集');
  await page.locator('#apply-key-text').click();
  assert.ok((await page.locator('#entry-text-feedback').innerText()).includes('文字を変更しました'));
  assert.ok((await page.locator('#save-info').innerText()).includes('未保存の編集'));
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), '共通Web編集');
  assert.ok(await page.locator('button.key[data-entry-id="kana.a"] .flick-guide').count() >= 4,
    'editing default text must not discard Rust flick guides');
  assert.equal(await page.locator('#undo-edit').isEnabled(), true);

  await page.locator('#undo-edit').click();
  assert.equal(await page.locator('#entry-text-feedback').innerText(), '',
    'Undo must clear stale Key success feedback');
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), original);
  await page.locator('#redo-edit').click();
  assert.equal((await page.locator('button.key[data-entry-id="kana.a"] .key-label').innerText()).trim(), '共通Web編集');

  await page.locator('#profile-title').fill('Web動作確認');
  await page.locator('#rename-profile').click();
  assert.ok((await page.locator('#profile-name').innerText()).includes('Web動作確認'));

  // M3j: every Key shows a discoverable Macro surface before any Macro exists.
  assert.ok((await page.locator('#key-macro-assigned').innerText()).includes('割当なし'));
  assert.equal(await page.locator('#key-macro-picker').isDisabled(), true);
  assert.equal(await page.locator('#key-macro-open-editor').isVisible(), true);
  // M3h: real mobile Chromium/Wasm, Rust is the Macro ID/name/action owner.
  assert.equal(await page.locator('#macro-select option').count(), 0);
  await page.locator('#macro-create-sample').click();
  assert.equal(await page.locator('#macro-select option').count(), 1);
  assert.ok((await page.locator('#macro-selected-meta').innerText()).includes('アクション 1 件'));
  assert.ok(!(await page.locator('#macro-selected-meta').innerText()).includes('macro.user.'));
  assert.equal(await page.locator('#macro-advanced').evaluate(el => el.open), false);
  await page.locator('#macro-advanced summary').click();
  assert.ok((await page.locator('#macro-internal-id').innerText()).includes('macro.user.'));
  await page.locator('#macro-advanced summary').click();
  assert.ok((await page.locator('#macro-feedback').innerText()).includes('サンプルMacroを作成しました'));
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
  assert.ok((await page.locator('#macro-feedback').innerText()).includes('マクロを作成できません'));
  assert.equal(await page.locator('#macro-feedback').getAttribute('data-result'), 'error');
  assert.equal(await page.locator('#macro-create-name').inputValue(), '  共有マクロ  ');
  // The failed Rust validation must not alter the Macro list or the typed input.
  assert.ok((await page.locator('#macro-feedback').boundingBox()).height > 0);
  assert.equal(await page.locator('#macro-select option').count(), 1, 'duplicate name must be rejected atomically');
  await page.locator('#macro-new-action').click();
  await page.locator('#macro-action-type').selectOption('noop');
  await page.locator('#macro-add-action').click();
  assert.ok((await page.locator('#macro-action-feedback').innerText()).includes('アクションを追加しました'));
  assert.equal(await page.locator('#macro-action-feedback').getAttribute('data-result'), 'success');
  assert.equal(await page.locator('#macro-actions option').count(), 2);
  assert.ok((await page.locator('#macro-actions option').last().innerText()).includes('何もしない'));
  console.log('M3h Macro create/rename/duplicate reject/action-edit/Undo/Redo via canonical Rust PASS');

  // M3j: attach a Macro *at the selected Key*, preserve existing Key context.
  const keyBindingList = page.locator('#key-macro-assigned');
  const keyBindingPicker = page.locator('#key-macro-picker');
  assert.ok((await keyBindingList.innerText()).includes('割当なし'));
  assert.equal(await page.locator('#key-macro-attach').isDisabled(), true);
  await keyBindingPicker.selectOption({label: '共有マクロ'});
  await page.locator('#key-macro-attach').click();
  assert.ok((await keyBindingList.innerText()).includes('共有マクロ'));
  assert.equal(await keyBindingList.locator('button').count(), 1);
  assert.ok((await page.locator('#key-macro-feedback').innerText()).includes('割り当てました'));
  assert.ok((await page.locator('#save-info').innerText()).includes('未保存の編集'));
  assert.ok((await page.locator('#selected-key').innerText()).length > 0);
  await page.locator('#undo-edit').click();
  assert.ok((await keyBindingList.innerText()).includes('割当なし'));
  await page.locator('#redo-edit').click();
  assert.ok((await keyBindingList.innerText()).includes('共有マクロ'));

  // Two independent Macro calls must coexist; one removal never deletes the other.
  await page.locator('#macro-create-name').fill('補助マクロ');
  await page.locator('#macro-create').click();
  await keyBindingPicker.selectOption({label: '補助マクロ'});
  await page.locator('#key-macro-attach').click();
  assert.equal(await keyBindingList.locator('button').count(), 2);

  // A deliberately injected duplicate reaches Rust as an unchanged/no-op command.
  const assignedId = await keyBindingList.locator('button').first().getAttribute('data-macro-id');
  await keyBindingPicker.evaluate((el, id) => {
    const option = document.createElement('option');
    option.value = id; option.textContent = 'duplicate fixture';
    el.append(option); el.value = id;
    el.dispatchEvent(new Event('change', {bubbles: true}));
  }, assignedId);
  await page.locator('#key-macro-attach').click();
  assert.ok((await page.locator('#key-macro-feedback').innerText()).includes('既に割り当て済み'));
  assert.equal(await keyBindingList.locator('button').count(), 2);

  // Rust must reject a missing Macro without losing selected Key/input or actions.
  await keyBindingPicker.evaluate(el => {
    const option = document.createElement('option');
    option.value = 'macro.missing'; option.textContent = 'invalid fixture';
    el.append(option); el.value = option.value;
    el.dispatchEvent(new Event('change', {bubbles: true}));
  });
  await page.locator('#key-macro-attach').click();
  assert.ok((await page.locator('#key-macro-feedback').innerText()).includes('割当失敗'));
  assert.equal(await keyBindingPicker.inputValue(), 'macro.missing');
  assert.equal(await keyBindingList.locator('button').count(), 2);
  assert.equal(await page.locator('#selected-key').isVisible(), true);

  await keyBindingList.locator('button').first().click();
  assert.equal(await keyBindingList.locator('button').count(), 1);
  await page.locator('#undo-edit').click();
  assert.equal(await keyBindingList.locator('button').count(), 2);
  await page.locator('#redo-edit').click();
  assert.equal(await keyBindingList.locator('button').count(), 1);
  assert.ok((await page.locator('#key-macro-guide').innerText()).includes('実キーボードでの実行は未確認'));
  await page.locator('#save-local').click();
  // IndexedDB writeDraft is asynchronous; a reload before durable completion
  // tests a race, not a persisted Macro roundtrip.
  await page.waitForFunction(() =>
    document.querySelector('#save-info')?.textContent?.includes('ブラウザに保存済'));
  await page.reload({waitUntil: 'domcontentloaded'});
  await page.locator('button.key[data-entry-id="kana.a"]').waitFor();
  assert.equal(await page.locator('#app').getAttribute('data-workspace'), 'test',
    'relaunch defaults to simple verification, not editing');
  await page.locator('#mode-edit').click();
  await page.locator('button.key[data-entry-id="kana.a"]').click();
  assert.equal(await page.locator('#key-macro-assigned button').count(), 1);
  assert.ok((await page.locator('#save-info').innerText()).includes('ブラウザに保存済'));
  // Narrow-screen + keyboard-accessible controls: no offscreen Key Macro editor.
  await page.setViewportSize({width: 320, height: 844});
  const visibleFeedbackWidth = await page.locator('#gesture-feedback').evaluate(el => ({
    actual: el.getBoundingClientRect().width,
    viewport: window.innerWidth
  }));
  assert.ok(visibleFeedbackWidth.actual <= visibleFeedbackWidth.viewport,
    'gesture feedback must fit the 320px mobile viewport without horizontal overflow');
  await page.locator('button.key[data-entry-id="kana.a"]').scrollIntoViewIfNeeded();
  const narrowKey = page.locator('button.key[data-entry-id="kana.a"]');
  const narrowKeyBox = await narrowKey.boundingBox();
  await page.mouse.move(narrowKeyBox.x + narrowKeyBox.width / 2, narrowKeyBox.y + narrowKeyBox.height / 2);
  await page.mouse.down();
  const narrowPopupBounds = await page.locator('#flick-popup').evaluate(el => {
    const p = el.getBoundingClientRect(), b = document.querySelector('#board').getBoundingClientRect();
    return {left:p.left, right:p.right, boardLeft:b.left, boardRight:b.right, viewport:innerWidth};
  });
  assert.ok(narrowPopupBounds.left >= narrowPopupBounds.boardLeft - 2
    && narrowPopupBounds.right <= narrowPopupBounds.boardRight + 2
    && narrowPopupBounds.right <= narrowPopupBounds.viewport,
    'on-key Rust hint popup must fit 320px without offscreen overflow');
  await page.screenshot({path: join(process.env.RUNNER_TEMP || '.', 'flick-popup-mobile-320.png')});
  await page.mouse.up();
  assert.equal(await page.locator('#flick-popup').count(), 0);
  const keyMacroBounds = await page.locator('.key-macro-editor').evaluate(el => ({
    width: el.getBoundingClientRect().width, screen: window.innerWidth
  }));
  assert.ok(keyMacroBounds.width <= keyMacroBounds.screen,
    'Key-local Macro editor must fit 320px screens');
  await page.locator('#key-macro-picker').focus();
  assert.equal(await page.evaluate(() => document.activeElement?.id), 'key-macro-picker');
  await page.setViewportSize({width: 390, height: 844});
  console.log('M3j Key Macro attach/multiple/no-op/invalid/Undo/Redo/save-reload and 320px focus PASS');


  await page.locator('#save-local').click();
  await page.waitForFunction(() => document.querySelector('#save-info')?.textContent?.includes('ブラウザに保存済'));
  assert.ok((await page.locator('#save-info').innerText()).includes('未反映'));

  await page.reload({waitUntil: 'domcontentloaded'});
  await page.waitForFunction(() => document.querySelector('#rust-status')?.textContent === 'Rust稼働中', null, {timeout: 25000});
  await page.locator('button.key[data-entry-id="kana.a"]').waitFor();
  await page.locator('#mode-edit').click();
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
