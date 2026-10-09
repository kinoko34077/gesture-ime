import {readDraft, writeDraft} from './host-browser.js';
// Shared editor-shell foundation. Input semantics come exclusively from Rust Wasm.
const $ = (id) => document.getElementById(id);
const state = { core: null, profileJSON: '', source: '', document: null, inspected: null, selected: null, activePointer: null, editor: null, savedJSON: null, baselineJSON: null, viewLayerId: null, viewBoardId: null, macroId: null, macroActionIndex: -1 };
const MAX_LOCAL_FILE_BYTES = 2_000_000;
const MAX_POINTER_EVENTS = 120;

function status(message, failed = false) {
  $('status').textContent = message;
  $('status').style.color = failed ? '#b22340' : '';
}
function escapeFileName(name) {
  return (name || 'profile').replace(/[^\p{L}\p{N}._-]+/gu, '_').slice(0, 70);
}
function authoredBaseText(boardId, entryId) {
  const board = state.document?.boards?.find(b => b.id === boardId);
  const entry = board?.entries?.find(e => e.id === entryId);
  return entry?.resolver?.default?.presentation?.text?.base || '';
}
function authoredDefaultTransition(boardId, entryId) {
  // Read-only initial value for editor widgets. The Rust editor alone validates
  // and mutates default transition semantics.
  const board = state.document?.boards?.find(item => item.id === boardId);
  const key = board?.entries?.find(item => item.id === entryId);
  return key?.resolver?.default?.transition ?? null;
}
function updateTransitionControls(entry) {
  const target = $('entry-transition-board');
  const lifetime = $('entry-transition-lifetime');
  const apply = $('apply-entry-transition');
  target.replaceChildren();
  const none = document.createElement('option');
  none.value = '';
  none.textContent = 'なし（遷移を解除）';
  target.append(none);
  for (const board of state.inspected?.profile?.boards ?? []) {
    const option = document.createElement('option');
    option.value = board.id;
    option.textContent = board.id;
    target.append(option);
  }
  const authored = entry
    ? authoredDefaultTransition(state.inspected.profile.boardId, entry.id)
    : null;
  target.value = authored?.targetBoardRef ?? '';
  lifetime.value = authored?.lifetime ?? 'transient';
  target.disabled = !entry;
  lifetime.disabled = !entry || !target.value;
  apply.disabled = !entry;
}
function setSelected(entry) {
  state.selected = entry;
  $('selected-key').textContent = entry ? entry.id : 'なし';
  document.querySelectorAll('.key').forEach(key => key.classList.toggle('selected', key.dataset.entryId === entry?.id));
  $('entry-text').disabled = !entry;
  $('apply-key-text').disabled = !entry;
  $('entry-text').value = entry ? authoredBaseText(state.inspected.profile.boardId, entry.id) : '';
  updateTransitionControls(entry);
}
function editorSnapshot() {
  if (!state.editor) throw new Error('編集エンジンを読み込んでいません');
  const result = JSON.parse(state.editor.snapshot());
  if (!result.ok || !result.snapshot) throw new Error(result.error || '編集状態の取得に失敗');
  return result.snapshot;
}

function hasUnsavedEdits() {
  if (!state.editor) return false;
  const comparison = state.savedJSON ?? state.baselineJSON;
  return editorSnapshot().profileJSON !== comparison;
}

function canReplayCurrentBoard() {
  const profile = state.inspected?.profile;
  return !!profile && state.viewLayerId === profile.initialLayerId
    && state.viewBoardId === profile.initialBoardId;
}

function renderBoardPickers() {
  const profile = state.inspected.profile;
  const layers = $('layer-picker');
  const boards = $('board-picker');
  layers.replaceChildren();
  boards.replaceChildren();
  for (const layer of profile.layers) {
    const option = document.createElement('option');
    option.value = layer.id;
    option.textContent = (layer.name || layer.id) + ' · ' + layer.id;
    layers.append(option);
  }
  for (const board of profile.boards) {
    const option = document.createElement('option');
    option.value = board.id;
    option.textContent = board.id + '（' + board.entryCount + 'キー）';
    boards.append(option);
  }
  layers.value = state.viewLayerId;
  boards.value = state.viewBoardId;
  layers.disabled = false;
  boards.disabled = false;
  $('board-preview-state').textContent = canReplayCurrentBoard()
    ? '初期Board · タップ／フリックを共通Rustで検証'
    : '編集専用プレビュー · 内部Boardからの操作再生は未対応';
  $('board-preview-state').dataset.mode = canReplayCurrentBoard() ? 'replay' : 'edit';
}

function inspectSelectedBoard(profileJSON) {
  if (!state.viewLayerId || !state.viewBoardId) {
    const first = JSON.parse(state.core.inspect_profile(profileJSON));
    if (!first.ok) throw new Error(first.error || '初期Boardの検証に失敗');
    state.viewLayerId = first.profile.initialLayerId;
    state.viewBoardId = first.profile.initialBoardId;
    return first;
  }
  const inspected = JSON.parse(state.core.inspect_board(
    profileJSON, state.viewLayerId, state.viewBoardId
  ));
  if (!inspected.ok) throw new Error(inspected.error || '選択Boardの検証に失敗');
  return inspected;
}

function chooseBoard(layerId, boardId) {
  if (!state.editor) return;
  const oldLayer = state.viewLayerId;
  const oldBoard = state.viewBoardId;
  try {
    state.viewLayerId = layerId;
    state.viewBoardId = boardId;
    const next = inspectSelectedBoard(state.profileJSON);
    state.inspected = next;
    setSelected(null);
    renderBoardPickers();
    renderBoard();
    $('trace-state').textContent = canReplayCurrentBoard()
      ? 'キーを操作してRustの判定を確認できます。'
      : 'このBoardはキー編集・表示のみ対応しています。';
    $('trace-actions').textContent = '—';
  } catch (error) {
    state.viewLayerId = oldLayer;
    state.viewBoardId = oldBoard;
    status('Boardを表示できません: ' + String(error), true);
    renderBoardPickers();
  }
}

function refreshEditor(snapshot, selectedId = state.selected?.id) {
  const inspected = inspectSelectedBoard(snapshot.profileJSON);
  state.profileJSON = snapshot.profileJSON;
  state.document = JSON.parse(snapshot.profileJSON);
  state.inspected = inspected;
  $('profile-name').textContent = snapshot.name + ' · ' + state.source;
  $('profile-title').value = snapshot.name;
  $('profile-title').disabled = false;
  $('rename-profile').disabled = false;
  $('undo-edit').disabled = !snapshot.canUndo;
  $('redo-edit').disabled = !snapshot.canRedo;
  $('save-local').disabled = false;
  $('export-profile').disabled = false;
  $('save-info').textContent = state.savedJSON === snapshot.profileJSON
    ? 'ブラウザに保存済 · iOS／Androidには未反映'
    : state.baselineJSON === snapshot.profileJSON
      ? '未変更・端末未保存 · iOS／Androidには未反映'
      : '未保存の編集 · iOS／Androidには未反映';
  renderBoardPickers();
  renderBoard();
  setSelected(inspected.profile.entries.find(e => e.id === selectedId) || null);
  renderMacroEditor();
}

function loadEditor(profileJSON, source, saved = false) {
  const editor = new state.core.WebProfileEditor(profileJSON);
  const result = JSON.parse(editor.snapshot());
  if (!result.ok || !result.snapshot) throw new Error(result.error || 'Profileを開けません');
  state.editor = editor;
  state.source = source;
  state.baselineJSON = result.snapshot.profileJSON;
  state.savedJSON = saved ? result.snapshot.profileJSON : null;
  state.viewLayerId = null;
  state.viewBoardId = null;
  state.macroId = null;
  state.macroActionIndex = -1;
  $('trace-state').textContent = 'キーを押すと結果が表示されます。';
  $('trace-actions').textContent = '—';
  refreshEditor(result.snapshot, null);
  status('共通Rust編集エンジンでProfileを読み込みました。');
}

function applyEditorResult(resultText, action) {
  const output = JSON.parse(resultText);
  if (!output.ok) throw new Error(output.error || action + 'に失敗しました');
  refreshEditor(output.snapshot);
  status(action + (output.changed ? 'しました。' : '（変更なし）。'));
  return output;
}
function applyCommand(command, action) {
  const revision = editorSnapshot().revision;
  return applyEditorResult(state.editor.apply_command(JSON.stringify(command), revision), action);
}

/* Browser controls reflect validated Rust Profile data. JavaScript assembles only
 * revisioned command payloads; it never runs/interprets Macro semantics. */
function selectedMacro() {
  return state.document?.macros?.find(m => m.id === state.macroId) ?? null;
}
function macroActionLabel(a, i) {
  if (a.actionID === 'text.insert') return (i + 1) + '. 文字入力: ' + String(a.arguments?.text?.base ?? '').slice(0, 35);
  if (a.actionID === 'noop') return (i + 1) + '. 何もしない';
  return (i + 1) + '. 詳細編集未対応: ' + a.actionID;
}
function renderMacroActionControls() {
  const m = selectedMacro();
  const a = state.macroActionIndex >= 0 ? m?.actions[state.macroActionIndex] : null;
  const selected = Boolean(a);
  const supported = !a || a.actionID === 'text.insert' || a.actionID === 'noop';
  $('macro-actions').value = selected ? String(state.macroActionIndex) : '';
  const type = $('macro-action-type');
  type.value = selected && supported ? a.actionID : 'text.insert';
  type.disabled = !m || !supported;
  $('macro-action-text').value = selected && a.actionID === 'text.insert'
    ? String(a.arguments?.text?.base ?? '') : '';
  $('macro-action-text').disabled = !m || !supported || type.value !== 'text.insert';
  $('macro-new-action').disabled = !m;
  $('macro-add-action').disabled = !m || !supported;
  $('macro-edit-action').disabled = !m || !selected || !supported;
  $('macro-remove-action').disabled = !m || !selected || !supported;
  $('macro-action-hint').textContent = selected && !supported
    ? 'この既存アクションは読み取り専用です。別の編集でも保持されます。'
    : !m ? 'まずマクロを作成または選択してください。'
      : selected ? '選択アクションを編集できます。文字入力の変換指定等は保持します。'
        : '新しいアクションを末尾に追加できます。';
}
function renderMacroEditor() {
  const macros = state.document?.macros ?? [];
  const previousId = state.macroId;
  const select = $('macro-select');
  select.replaceChildren();
  for (const m of macros) {
    const option = document.createElement('option');
    option.value = m.id;
    option.textContent = m.name || '(名前未設定のMacro)';
    select.append(option);
  }
  if (!macros.some(m => m.id === state.macroId)) {
    state.macroId = macros[0]?.id ?? null;
    state.macroActionIndex = -1;
  }
  select.disabled = !macros.length;
  select.value = state.macroId ?? '';
  const m = selectedMacro();
  const list = $('macro-actions');
  list.replaceChildren();
  for (const [i, a] of (m?.actions ?? []).entries()) {
    const option = document.createElement('option');
    option.value = String(i);
    option.textContent = macroActionLabel(a, i);
    list.append(option);
  }
  if (state.macroActionIndex >= (m?.actions?.length ?? 0)) state.macroActionIndex = -1;
  if (previousId !== state.macroId) state.macroActionIndex = -1;
  list.disabled = !m || !m.actions.length;
  $('macro-name').value = m?.name ?? '';
  $('macro-name').disabled = !m;
  $('macro-rename').disabled = !m;
  $('macro-selected-meta').textContent = m
    ? '内部ID: ' + m.id + ' / アクション ' + m.actions.length + ' 件'
    : 'マクロがありません。名前を入力して新規作成できます。';
  renderMacroActionControls();
}
function actionFromForm(previous = null) {
  const type = $('macro-action-type').value;
  if (type === 'noop') return previous?.actionID === 'noop'
    ? JSON.parse(JSON.stringify(previous)) : {actionID: 'noop', arguments: {}};
  if (type !== 'text.insert') throw new Error('このアクションは編集できません');
  const text = $('macro-action-text').value;
  if (previous?.actionID === 'text.insert') {
    const copy = JSON.parse(JSON.stringify(previous));
    copy.arguments.text.base = text; // Preserve conditional transforms/unknown extra metadata.
    return copy;
  }
  return {actionID: 'text.insert', arguments: {text: {base: text, transforms: []}}};
}
function createMacro(name, actions, description) {
  const before = new Set((state.document?.macros ?? []).map(m => m.id));
  applyCommand({type: 'createMacro', name, actions}, description);
  const newItem = state.document.macros.find(m => !before.has(m.id));
  if (!newItem) throw new Error('Rust作成後のMacroがありません');
  state.macroId = newItem.id;
  state.macroActionIndex = newItem.actions.length ? 0 : -1;
  renderMacroEditor();
}
function updateMacroActions(update, label) {
  const m = selectedMacro();
  if (!m) throw new Error('マクロを選択してください');
  const actions = JSON.parse(JSON.stringify(m.actions)); // payload copy, NOT persisted semantics
  update(actions);
  applyCommand({type: 'setMacroActions', macroId: m.id, actions}, label);
  renderMacroEditor();
}

async function saveCurrentDraft() {
  const snapshot = editorSnapshot();
  await writeDraft(snapshot.profileId, snapshot.profileJSON);
  state.savedJSON = snapshot.profileJSON;
  refreshEditor(snapshot);
  status('このブラウザに保存しました。実キーボードには未反映です。');
}

function renderBoard() {
  const boardEl = $('board');
  boardEl.replaceChildren();
  const profile = state.inspected.profile;
  const items = profile.entries;
  $('board-count').textContent = items.length + ' キー';
  if (!items.length) {
    status('このBoardにはキーがありません。');
    return;
  }
  const minX = Math.min(...items.map(e => e.rect.x));
  const minY = Math.min(...items.map(e => e.rect.y));
  const maxX = Math.max(...items.map(e => e.rect.x + e.rect.width));
  const maxY = Math.max(...items.map(e => e.rect.y + e.rect.height));
  const cols = Math.max(1, maxX - minX);
  const rows = Math.max(1, maxY - minY);
  boardEl.style.gridTemplateColumns = 'repeat(' + cols + ',minmax(0,1fr))';
  boardEl.style.gridTemplateRows = 'repeat(' + rows + ',minmax(44px,1fr))';
  for (const entry of items) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'key';
    btn.dataset.entryId = entry.id;
    btn.style.gridColumn = (entry.rect.x - minX + 1) + ' / span ' + entry.rect.width;
    btn.style.gridRow = (entry.rect.y - minY + 1) + ' / span ' + entry.rect.height;
    const text = entry.text ?? authoredBaseText(profile.boardId, entry.id) ?? entry.id;
    const label = document.createElement('span');
    label.className = 'key-label';
    label.textContent = text || entry.id;
    btn.append(label);
    // Guide labels and center coordinates are resolved by canonical Rust
    // ProfileV3PlatformRuntime::direct_surface (including source overrides).
    const guides = Array.isArray(entry.guides)
      ? entry.guides.filter(g => g.label && Number.isFinite(g.centerX) && Number.isFinite(g.centerY))
      : [];
    if (guides.length) {
      btn.classList.add('has-flick-guides');
      for (const guide of guides) {
        const badge = document.createElement('span');
        badge.className = 'flick-guide';
        badge.textContent = guide.label;
        badge.dataset.targetEntryId = guide.targetEntryId;
        badge.style.left = (50 + Math.max(-1.5, Math.min(1.5, guide.centerX)) * 24) + '%';
        badge.style.top = (50 + Math.max(-1.5, Math.min(1.5, guide.centerY)) * 24) + '%';
        badge.setAttribute('aria-hidden', 'true');
        btn.append(badge);
      }
    }
    btn.setAttribute('aria-label', 'キー ' + (text || entry.id) + '、ID ' + entry.id
      + (guides.length ? '、フリック候補 ' + guides.map(g => g.label).join('、') : ''));
    if (canReplayCurrentBoard()) {
      btn.addEventListener('pointerdown', event => startPointer(event, btn, entry, cols, rows));
      btn.addEventListener('pointermove', updatePointer);
      btn.addEventListener('pointerup', event => finishPointer(event, false));
      btn.addEventListener('pointercancel', event => finishPointer(event, true));
    } else {
      btn.addEventListener('click', () => setSelected(entry));
    }
    boardEl.append(btn);
  }
}
function eventMs(active) {
  return Math.max(active.lastTime, Math.floor(performance.now() - active.startedAt));
}
function startPointer(event, btn, entry, cols, rows) {
  if (state.activePointer || !event.isPrimary) return;
  event.preventDefault();
  const boardBox = $('board').getBoundingClientRect();
  const now = performance.now();
  state.activePointer = {
    pointerId: event.pointerId, element: btn, entryId: entry.id, x: event.clientX, y: event.clientY,
    startedAt: now, lastTime: 0, lastMoveTime: 0, events: [],
    cellWidth: boardBox.width / cols, cellHeight: boardBox.height / rows,
  };
  btn.classList.add('pressed');
  setSelected(entry);
  try { btn.setPointerCapture(event.pointerId); } catch (_) { /* capture unavailable */ }
}
function updatePointer(event) {
  const a = state.activePointer;
  if (!a || event.pointerId !== a.pointerId) return;
  const atMs = eventMs(a);
  if (atMs - a.lastMoveTime < 20 || a.events.length >= MAX_POINTER_EVENTS) return;
  a.lastTime = atMs;
  a.lastMoveTime = atMs;
  a.events.push({kind: 'move', x: event.clientX - a.x, y: event.clientY - a.y, atMs});
}
function finishPointer(event, cancel) {
  const a = state.activePointer;
  if (!a || event.pointerId !== a.pointerId) return;
  event.preventDefault();
  const atMs = eventMs(a);
  a.element.classList.remove('pressed');
  state.activePointer = null;
  const events = a.events;
  // Always advance time in canonical Rust; it alone determines per-entry Hold thresholds.
  if (!cancel) events.push({kind: 'advance', atMs});
  events.push({kind: cancel ? 'cancel' : 'up', atMs});
  const script = {
    entryId: a.entryId, cellWidth: a.cellWidth, cellHeight: a.cellHeight,
    touchDown: {x: 0, y: 0}, startMs: 0, events,
  };
  try {
    const result = JSON.parse(state.core.trace_profile(state.profileJSON, JSON.stringify(script)));
    if (!result.ok) throw new Error(result.error);
    const samples = result.trace.samples;
    const last = samples[samples.length - 1];
    $('trace-state').textContent = [last.boardId, 'Stage ' + last.stageDepth,
      last.context, last.terminal || '処理中', '候補: ' + (last.candidateEntryId || '—')].join(' / ');
    const actions = last.dispatchedActions || [];
    $('trace-actions').textContent = actions.length ? JSON.stringify(actions, null, 2) : '発行された命令はありません';
    status('Rust判定を実行しました（ブラウザ内のみ）。');
  } catch (error) {
    status('操作を検証できません: ' + String(error?.message || error), true);
  }
}
async function loadBuiltIn(preferSaved = true) {
  const response = await fetch('./default-ja.json');
  if (!response.ok) throw new Error('組み込みProfileの取得に失敗: ' + response.status);
  const sample = await response.text();
  let profile = sample;
  let saved = false;
  if (preferSaved) {
    try {
      const result = JSON.parse(state.core.inspect_profile(sample));
      if (!result.ok) throw new Error(result.error);
      const local = await readDraft(result.profile.id);
      if (local) {
        const check = JSON.parse(state.core.inspect_profile(local));
        if (!check.ok) throw new Error('保存Profileが無効です: ' + check.error);
        profile = local;
        saved = true;
      }
    } catch (error) {
      status('ブラウザ保存を読めません。組み込みProfileで起動します: ' + String(error), true);
    }
  }
  loadEditor(profile, saved ? 'この端末の保存データ' : '公開サンプル', saved);
}
function exportProfile() {
  if (!state.profileJSON) return;
  const blob = new Blob([state.profileJSON], {type: 'application/json'});
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = escapeFileName(state.inspected.profile.id) + '.json';
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}
async function boot() {
  try {
    state.core = await import('./wasm/gesture_ime_core_web.js');
    await state.core.default(new URL('./wasm/gesture_ime_core_web_bg.wasm', import.meta.url));
    await loadBuiltIn();
    // Do not signal ready until the validated Profile and saved local draft
    // have actually hydrated. Wasm initialization alone is not UI readiness.
    $('rust-status').textContent = 'Rust稼働中';
  } catch (error) {
    $('rust-status').textContent = '初期化失敗';
    status('Rustモジュールを読み込めません: ' + String(error?.message || error), true);
  }
}
$('profile-file').addEventListener('change', async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  try {
    if (file.size > MAX_LOCAL_FILE_BYTES) throw new Error('2 MBを超えるファイルは扱えません');
    if (!state.core) throw new Error('Rustを初期化できていません');
    if (hasUnsavedEdits() && !window.confirm('未保存の編集を破棄して別のProfileを開きますか？')) return;
    loadEditor(await file.text(), '端末内から読込');
  } catch (error) {
    status('Profileが無効です: ' + String(error?.message || error), true);
  } finally {
    event.target.value = '';
  }
});
$('reset-profile').addEventListener('click', async () => {
  if (hasUnsavedEdits() && !window.confirm('未保存の編集を破棄して初期Profileに戻しますか？')) return;
  try { await loadBuiltIn(false); } catch (error) { status(String(error), true); }
});
$('export-profile').addEventListener('click', exportProfile);
$('save-local').addEventListener('click', () => saveCurrentDraft().catch(error => status('保存失敗: ' + String(error), true)));
$('undo-edit').addEventListener('click', () => {
  try { applyEditorResult(state.editor.undo(), 'Undo'); } catch(error) { status(String(error), true); }
});
$('redo-edit').addEventListener('click', () => {
  try { applyEditorResult(state.editor.redo(), 'Redo'); } catch(error) { status(String(error), true); }
});
$('rename-profile').addEventListener('click', () => {
  try { applyCommand({type: 'renameProfile', name: $('profile-title').value}, 'Profile名を変更'); }
  catch(error) { status('名前変更失敗: ' + String(error), true); }
});
$('apply-key-text').addEventListener('click', () => {
  if (!state.selected) return;
  try {
    applyCommand({type: 'setEntryDefaultText', boardId: state.inspected.profile.boardId, entryId: state.selected.id, text: $('entry-text').value}, 'キー文字を変更');
  } catch(error) { status('キー編集失敗: ' + String(error), true); }
});
$('entry-transition-board').addEventListener('change', event => {
  $('entry-transition-lifetime').disabled = !state.selected || !event.target.value;
});
$('apply-entry-transition').addEventListener('click', () => {
  if (!state.selected) return;
  const target = $('entry-transition-board').value;
  const lifetime = target ? $('entry-transition-lifetime').value : null;
  try {
    applyCommand({
      type: 'setEntryDefaultTransition',
      boardId: state.inspected.profile.boardId,
      entryId: state.selected.id,
      targetBoardId: target || null,
      lifetime
    }, '標準遷移を変更');
  } catch (error) {
    status('遷移変更失敗: ' + String(error), true);
  }
});

$('macro-select').addEventListener('change', event => {
  state.macroId = event.target.value;
  state.macroActionIndex = -1;
  renderMacroEditor();
});
$('macro-create').addEventListener('click', () => {
  try { createMacro($('macro-create-name').value, [], 'マクロを作成'); }
  catch (e) { status('Macro作成失敗: ' + String(e), true); }
});
$('macro-create-sample').addEventListener('click', () => {
  try {
    createMacro('サンプル：あいさつ', [{
      actionID: 'text.insert', arguments: {text: {base: 'こんにちは！', transforms: []}}
    }], 'サンプルMacroを作成');
  } catch (e) { status('サンプル作成失敗: ' + String(e), true); }
});
$('macro-rename').addEventListener('click', () => {
  const m = selectedMacro();
  if (!m) return;
  try { applyCommand({type: 'renameMacro', macroId: m.id, name: $('macro-name').value}, 'マクロ名を変更'); }
  catch (e) { status('Macro改名失敗: ' + String(e), true); }
});
$('macro-actions').addEventListener('change', event => {
  state.macroActionIndex = Number(event.target.value);
  renderMacroActionControls();
});
$('macro-new-action').addEventListener('click', () => {
  state.macroActionIndex = -1;
  renderMacroActionControls();
  $('macro-action-type').focus();
});
$('macro-action-type').addEventListener('change', () => {
  $('macro-action-text').disabled = $('macro-action-type').value !== 'text.insert';
});
$('macro-add-action').addEventListener('click', () => {
  const m = selectedMacro(); if (!m) return;
  try {
    const old = state.macroActionIndex >= 0 ? m.actions[state.macroActionIndex] : null;
    updateMacroActions(actions => actions.push(actionFromForm(old)), 'アクションを追加');
    state.macroActionIndex = m.actions.length;
    renderMacroEditor();
  } catch (e) { status('アクション追加失敗: ' + String(e), true); }
});
$('macro-edit-action').addEventListener('click', () => {
  const m = selectedMacro(), i = state.macroActionIndex;
  if (!m || i < 0 || i >= m.actions.length) return;
  try { updateMacroActions(actions => { actions[i] = actionFromForm(m.actions[i]); }, 'アクションを編集'); }
  catch (e) { status('アクション編集失敗: ' + String(e), true); }
});
$('macro-remove-action').addEventListener('click', () => {
  const m = selectedMacro(), i = state.macroActionIndex;
  if (!m || i < 0 || i >= m.actions.length) return;
  try {
    updateMacroActions(actions => actions.splice(i, 1), 'アクションを削除');
    state.macroActionIndex = -1;
    renderMacroEditor();
  } catch (e) { status('アクション削除失敗: ' + String(e), true); }
});

$('layer-picker').addEventListener('change', event => {
  const id = event.target.value;
  const layer = state.inspected.profile.layers.find(item => item.id === id);
  if (layer) chooseBoard(id, layer.rootBoardId);
});
$('board-picker').addEventListener('change', event => {
  chooseBoard(state.viewLayerId, event.target.value);
});
$('build-id').textContent = 'Profile v3 · Rust/Wasm';
boot();
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}
