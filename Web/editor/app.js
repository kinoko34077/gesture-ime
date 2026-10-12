import {readDraft, writeDraft} from './host-browser.js';
// Shared editor-shell foundation. Input semantics come exclusively from Rust Wasm.
const $ = (id) => document.getElementById(id);
const state = { core: null, profileJSON: '', source: '', document: null, inspected: null, selected: null, activePointer: null, editor: null, savedJSON: null, baselineJSON: null, viewLayerId: null, viewBoardId: null, macroId: null, macroActionIndex: -1, stageHistory: [] };
const STAGE_DIRECTIONS = [
  {id:'northWest', name:'左上', x:-3, y:-3}, {id:'north', name:'上', x:-1, y:-3},
  {id:'northEast', name:'右上', x:1, y:-3}, {id:'west', name:'左', x:-3, y:-1},
  {id:'east', name:'右', x:1, y:-1}, {id:'southWest', name:'左下', x:-3, y:1},
  {id:'south', name:'下', x:-1, y:1}, {id:'southEast', name:'右下', x:1, y:1}
];
const MAX_LOCAL_FILE_BYTES = 2_000_000;
const MAX_POINTER_EVENTS = 120;
const MAX_TEST_CHARACTERS = 2000;

// Browser-only display of actions dispatched by the canonical Rust BoardSession.
// It is never Profile input or proof of OS keyboard effects.
function renderTestOutput() {
  const el = $('test-output');
  el.dataset.empty = state.testOutput ? 'false' : 'true';
  el.textContent = state.testOutput || 'キーを押すと、入力された文字をここに表示します';
}
function setWorkspaceMode(mode) {
  const app = $('app');
  if (!['test','edit'].includes(mode) || !state.inspected) return;
  const previous = app.dataset.workspace;
  if (mode === 'test' && previous === 'edit') {
    state.editLocation = {layerId: state.viewLayerId, boardId: state.viewBoardId,
      entryId: state.selected?.id};
    const layer = state.inspected.profile.layers.find(item => item.id === state.viewLayerId);
    if (layer && layer.rootBoardId !== state.viewBoardId) chooseBoard(layer.id, layer.rootBoardId);
  } else if (mode === 'edit' && previous === 'test' && state.editLocation) {
    const prior = state.editLocation;
    state.editLocation = null;
    if (state.document?.boards.some(board => board.id === prior.boardId)
        && state.document?.layers.some(layer => layer.id === prior.layerId)) {
      chooseBoard(prior.layerId, prior.boardId);
      setSelected(state.inspected.profile.entries.find(entry => entry.id === prior.entryId) || null);
    }
  }
  app.dataset.workspace = mode;
  $('mode-test').classList.toggle('active', mode === 'test');
  $('mode-edit').classList.toggle('active', mode === 'edit');
  $('mode-test').setAttribute('aria-pressed', String(mode === 'test'));
  $('mode-edit').setAttribute('aria-pressed', String(mode === 'edit'));
  $('keyboard-heading').textContent = mode === 'test' ? 'キーボードを試す' : 'キーボードの編集';
  $('keyboard-subtitle').textContent = mode === 'test'
    ? 'キーを押して、下の入力結果で動作を確認してください。'
    : '編集対象のLayerとBoardを選び、キーを変更できます。';
}

function status(message, failed = false) {
  $('status').textContent = message;
  $('status').style.color = failed ? '#b22340' : '';
}
// Read-only guide rendering; candidate order/text comes from Rust direct_surface.
// Pointer movement does not guess selection in JavaScript.
function showRustGestureGuides(entry) {
  const region = $('gesture-guides');
  region.replaceChildren();
  const guides = (Array.isArray(entry?.guides) ? entry.guides : [])
    .filter(g => g.label && Number.isFinite(g.centerX) && Number.isFinite(g.centerY));
  for (const guide of guides) {
    const dx = Math.sign(guide.centerX), dy = Math.sign(guide.centerY);
    const direction = ({'-1,-1':'↖', '0,-1':'↑', '1,-1':'↗',
      '-1,0':'←', '1,0':'→', '-1,1':'↙', '0,1':'↓', '1,1':'↘'})
      [dx + ',' + dy] || '•';
    const item = document.createElement('span');
    item.className = 'gesture-guide-item';
    item.textContent = direction + ' ' + guide.label;
    region.append(item);
  }
  region.hidden = guides.length === 0;
}
// Visual-only popup: every direction/label is read from Rust's direct_surface.
// No pointer-distance threshold or candidate judgement exists in JavaScript.
function clearFlickPopup() {
  $('flick-popup')?.remove();
}
function showFlickPopup(entry, keyButton) {
  clearFlickPopup();
  const guides = (Array.isArray(entry?.guides) ? entry.guides : [])
    .filter(g => g.label && Number.isFinite(g.centerX) && Number.isFinite(g.centerY));
  if (!guides.length) return;
  const board = $('board');
  const popup = document.createElement('div');
  popup.id = 'flick-popup';
  popup.className = 'flick-popup';
  popup.setAttribute('aria-hidden', 'true'); // The accessible guide list remains above the keyboard.
  popup.dataset.sourceEntryId = entry.id;
  const cells = Array.from({length: 9}, (_, i) => {
    const cell = document.createElement('span');
    cell.className = 'flick-popup-cell';
    cell.dataset.direction = ['northWest', 'north', 'northEast',
      'west', 'center', 'east', 'southWest', 'south', 'southEast'][i];
    if (i === 4) {
      cell.classList.add('is-center');
      cell.textContent = entry.text || authoredBaseText(state.inspected.profile.boardId, entry.id) || entry.id;
    } else {
      cell.classList.add('is-empty');
    }
    popup.append(cell);
    return cell;
  });
  for (const guide of guides) {
    const col = Math.sign(guide.centerX) + 1;
    const row = Math.sign(guide.centerY) + 1;
    const index = row * 3 + col;
    if (index === 4) continue;
    const cell = cells[index];
    // Multiple Rust-provided guides at one position stay visible, never guessed.
    cell.textContent = cell.classList.contains('is-empty')
      ? guide.label : cell.textContent + '・' + guide.label;
    cell.classList.remove('is-empty');
  }
  board.append(popup);
  const boardBox = board.getBoundingClientRect();
  const keyBox = keyButton.getBoundingClientRect();
  const popupBox = popup.getBoundingClientRect();
  const centerX = keyBox.left - boardBox.left + keyBox.width / 2;
  const centerY = keyBox.top - boardBox.top + keyBox.height / 2;
  popup.style.left = Math.max(4, Math.min(centerX - popupBox.width / 2,
    boardBox.width - popupBox.width - 4)) + 'px';
  popup.style.top = Math.max(-14, centerY - popupBox.height / 2) + 'px';
}
function gestureOutcome(message, failed = false) {
  const element = $('gesture-result');
  element.textContent = message;
  element.dataset.result = failed ? 'error' : 'success';
}
function resetGestureOutcome() {
  clearFlickPopup();
  gestureOutcome('キーを押すと、ここにRustの判定が表示されます。');
  $('gesture-guides').replaceChildren();
  $('gesture-guides').hidden = true;
}
function describeRustAction(action) {
  const text = action?.arguments?.text?.base;
  if ((action?.actionID === 'text.insert' || action?.actionID === 'text.directInsert')
      && typeof text === 'string') return '文字「' + text + '」';
  return action?.actionID || '不明な命令';
}
function localMacroStatus(id, message, failed = false) {
  status(message, failed);
  const feedback = $(id);
  feedback.textContent = message;
  feedback.dataset.result = failed ? 'error' : 'success';
  // Do not leave stale feedback on the other Macro editing task.
  $(id === 'macro-feedback' ? 'macro-action-feedback' : 'macro-feedback').textContent = '';
}
function macroStatus(message, failed = false) {
  localMacroStatus('macro-feedback', message, failed);
}
function macroActionStatus(message, failed = false) {
  localMacroStatus('macro-action-feedback', message, failed);
}
// Edit results belong next to the selected key. The Rust command is the only validator.
function keyEditorStatus(id, message, failed = false) {
  const element = $(id);
  element.textContent = message;
  element.dataset.result = failed ? 'error' : 'success';
  status(message, failed);
}
function clearKeyEditorFeedback() {
  for (const id of ['entry-text-feedback', 'entry-transition-feedback', 'hold-feedback']) {
    const element = $(id);
    element.textContent = '';
    delete element.dataset.result;
  }
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
function selectedKeyDocument() {
  const board = state.document?.boards?.find(b => b.id === state.inspected?.profile?.boardId);
  return board?.entries?.find(e => e.id === state.selected?.id) ?? null;
}
// Projection of authored v3 Board rectangles, not an independent gesture hit engine.
function hasOrigin(entry) {
  const r = entry?.rect;
  return !!r && r.x <= 0 && r.y <= 0 && r.x + r.width > 0 && r.y + r.height > 0;
}
function stageBoardForSelected() {
  const key = selectedKeyDocument();
  if (!key) return null;
  const target = key.resolver?.default?.transition?.targetBoardRef;
  if (target) return state.document.boards.find(board => board.id === target) || null;
  const here = state.document.boards.find(board => board.id === state.viewBoardId);
  const layer = state.document.layers.find(layer => layer.id === state.viewLayerId);
  // Within a relative Board the entire 3×3 belongs to this stage, not a fresh
  // transition out of its origin. Root keys without a relative Board need
  // a separate canonical create-flick-Board command before editing.
  if (here && layer?.rootBoardRef !== here.id && here.entries.some(hasOrigin)) return here;
  return null;
}
function stageFeedback(message, failed = false) {
  const region = $('stage-feedback');
  region.textContent = message;
  region.dataset.result = failed ? 'error' : 'success';
  status(message, failed);
}
function renderStageEditor() {
  const grid = $('stage-grid');
  grid.replaceChildren();
  const board = stageBoardForSelected();
  $('stage-back').hidden = !state.stageHistory.length;
  const key = selectedKeyDocument();
  $('stage-location').textContent = !key
    ? 'キーボードからキーを選択してください。'
    : board ? '中央と8方向 · 空欄はまだ入力に使われません。'
      : 'このキーには方向の入力面がありません。先にフリック面の作成が必要です。';
  const makeCell = (name, label, stateName, direction = null, disabled = false) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'stage-cell';
    button.dataset.state = stateName;
    if (direction) button.dataset.direction = direction;
    button.disabled = disabled;
    button.setAttribute('aria-label', name + '：' + label);
    const heading = document.createElement('span');
    heading.textContent = name;
    const detail = document.createElement('small');
    detail.textContent = label;
    button.append(heading, detail);
    return button;
  };
  const cells = new Map(STAGE_DIRECTIONS.map(dir => [dir.x + ',' + dir.y, dir]));
  for (const y of [-3, -1, 1]) for (const x of [-3, -1, 1]) {
    if (x === -1 && y === -1) {
      const center = board?.entries.find(hasOrigin);
      const name = center?.resolver?.default?.presentation?.text?.base || '中央';
      grid.append(makeCell('中央', name, 'center', null, true));
      continue;
    }
    const d = cells.get(x + ',' + y);
    const overlaps = board?.entries.filter(e => e.rect.x < x + 2 && e.rect.x + e.rect.width > x
      && e.rect.y < y + 2 && e.rect.y + e.rect.height > y) ?? [];
    const exact = overlaps.length === 1 && overlaps[0].rect.x === x
      && overlaps[0].rect.y === y && overlaps[0].rect.width === 2 && overlaps[0].rect.height === 2;
    const entry = exact ? overlaps[0] : null;
    const defaultAction = entry?.resolver?.default;
    const advanced = !!entry && (entry.resolver.cases.length > 0 || !!defaultAction.hold);
    const transition = defaultAction?.transition?.targetBoardRef;
    const output = defaultAction?.presentation?.text?.base || defaultAction?.onRelease?.find(a => a.actionID === 'text.insert')?.arguments?.text?.base || '';
    let label = '+ 続き', stateName = 'empty', disabled = !board;
    if (overlaps.length && !exact || advanced) {
      label = '詳細編集が必要'; stateName = 'blocked'; disabled = true;
    } else if (transition) {
      label = '続きへ ▸'; stateName = 'existing';
    } else if (entry) {
      label = output ? output + ' · 続き' : '続き';
      stateName = 'existing';
    }
    grid.append(makeCell(d.name, label, stateName, d.id, disabled));
  }
}
function openStageBoard(targetId) {
  if (!state.document.boards.some(board => board.id === targetId)) throw new Error('遷移先の入力面がありません');
  state.stageHistory.push({layerId:state.viewLayerId, boardId:state.viewBoardId, entryId:state.selected?.id});
  chooseBoard(state.viewLayerId, targetId);
  const origin = state.inspected.profile.entries.find(entry => hasOrigin(entry));
  setSelected(origin || null);
}
function editDirection(directionId) {
  const direction = STAGE_DIRECTIONS.find(item => item.id === directionId);
  const board = stageBoardForSelected();
  if (!direction || !board) return;
  const entries = board.entries.filter(e => e.rect.x < direction.x + 2
    && e.rect.x + e.rect.width > direction.x && e.rect.y < direction.y + 2
    && e.rect.y + e.rect.height > direction.y);
  const entry = entries.length === 1 ? entries[0] : null;
  const existing = entry?.resolver?.default?.transition?.targetBoardRef;
  if (existing) {
    openStageBoard(existing);
    return;
  }
  // Rust performs final canonical collision, advanced-rule and overwrite checks.
  const nonempty = (entry?.resolver?.default?.onRelease?.length ?? 0) > 0;
  if (nonempty && !window.confirm('「' + direction.name + '」の現在の入力を、次の段階への遷移に置き換えますか？')) return;
  try {
    const ids = new Set(state.document.boards.map(b => b.id));
    const result = applyCommand({
      type: 'createDirectionalStage', boardId: board.id,
      direction: direction.id, replaceExistingOutput: nonempty
    }, '方向から次の段階を作成');
    if (!result.changed) {
      stageFeedback('この方向は変更されていません。');
      return;
    }
    const added = state.document.boards.filter(b => !ids.has(b.id));
    if (added.length !== 1) throw new Error('作成したStageの位置が不明です');
    openStageBoard(added[0].id);
    stageFeedback('「' + direction.name + '」の次の段階を作りました。戻るで元のキーに戻れます。');
  } catch (error) {
    stageFeedback('次の段階を作成できません: ' + String(error), true);
  }
}

// The canonical Rust editor alone creates a reachable Hold. This is a
// read-only path projection of validated authored source/relative-origin data,
// never a fabricated destination ID or duplicate gesture implementation.
function reachableHoldForSelected() {
  const source = selectedKeyDocument();
  if (!source) return null;
  const direct = source.resolver?.default?.hold;
  if (direct) return {
    hold: direct,
    target: direct.transition?.targetBoardRef || null
  };
  const relativeId = source.resolver?.default?.transition?.targetBoardRef;
  const relative = state.document?.boards?.find(board => board.id === relativeId);
  const origin = relative?.entries?.find(hasOrigin);
  const hold = origin?.resolver?.default?.hold;
  return hold ? {hold, target: hold.transition?.targetBoardRef || null} : {hold: null, target: null};
}
function renderHoldEditor() {
  const button = $('hold-open');
  const delay = $('hold-delay');
  const guide = $('hold-guide');
  const key = selectedKeyDocument();
  const layer = state.document?.layers?.find(item => item.id === state.viewLayerId);
  const root = layer?.rootBoardRef === state.viewBoardId;
  const linked = root && key ? reachableHoldForSelected() : null;
  const destination = linked?.target
    && state.document?.boards?.some(board => board.id === linked.target)
      ? linked.target : null;
  $('hold-back').hidden = !state.stageHistory.length;
  button.dataset.mode = destination ? 'open' : 'create';
  button.textContent = destination ? '長押しの入力面へ' : '長押しの入力面を作る';
  button.disabled = !root || !key || (!!linked?.hold && !destination);
  delay.disabled = !root || !key || !!linked?.hold;
  if (destination) {
    delay.value = String(linked.hold.delayMs);
    guide.textContent = '作成済みです。押すと長押し先の入力面を編集できます。';
  } else if (!key) {
    guide.textContent = 'まず編集したいキーを選択してください。';
  } else if (!root) {
    guide.textContent = '中央キーの表示文字を編集できます。入力する文字の動作設定は別機能です。前のキーに戻れます。';
  } else if (linked?.hold) {
    guide.textContent = '既存の詳細な長押し設定はこの簡易画面では開けません。';
  } else {
    guide.textContent = '新しい長押し専用の入力面を作ります。通常のタップとフリックは保持されます。';
  }
}
function returnToPreviousKey() {
  const prior = state.stageHistory.pop();
  if (!prior) return;
  chooseBoard(prior.layerId, prior.boardId);
  setSelected(state.inspected.profile.entries.find(item => item.id === prior.entryId) || null);
  $('stage-feedback').textContent = '';
  $('hold-feedback').textContent = '';
}
function openOrCreateHold() {
  const key = selectedKeyDocument();
  if (!key || !state.selected) return;
  const target = reachableHoldForSelected()?.target;
  if (target && state.document.boards.some(board => board.id === target)) {
    openStageBoard(target);
    keyEditorStatus('hold-feedback', '長押し先を開きました。中央キーの表示を編集できます（入力動作は別設定）。');
    return;
  }
  const delay = Number($('hold-delay').value);
  try {
    // Fail without mutation for empty/out-of-range/decimal entry; Rust also
    // validates 50–5000 and the complete reachable structure.
    if (!Number.isInteger(delay) || delay < 50 || delay > 5000 || !$('hold-delay').value.trim()) {
      throw new Error('長押しの時間は50〜5000ミリ秒の整数で指定してください');
    }
    const before = new Set(state.document.boards.map(b => b.id));
    const boardId = state.inspected.profile.boardId, entryId = state.selected.id;
    const result = applyCommand({type:'createReachableHoldSurface', boardId, entryId, delayMs:delay},
      '長押しの入力面を作成');
    if (!result.changed) {
      keyEditorStatus('hold-feedback', '変更はありません。');
      return;
    }
    // Inspect the actual Rust-edited Profile, never derive a target from
    // a generated ID naming convention.
    const destination = reachableHoldForSelected()?.target;
    if (!destination || before.has(destination)
        || !state.document.boards.some(board => board.id === destination)) {
      throw new Error('作成後の長押し先を確認できません');
    }
    openStageBoard(destination);
    keyEditorStatus('hold-feedback', '長押し先を作成しました。中央キーの表示を編集できます（入力動作は別設定）。');
  } catch (error) {
    keyEditorStatus('hold-feedback', '長押しを設定できません: ' + String(error?.message || error), true);
  }
}
function keyMacroBindingStatus(message, failed = false) {
  const el = $('key-macro-feedback');
  el.textContent = message;
  el.dataset.result = failed ? 'error' : 'success';
  status(message, failed);
}
// Display authored Macro references only. All changes/validation execute in Rust.
function updateKeyMacroBindings() {
  const key = selectedKeyDocument();
  const macros = state.document?.macros ?? [];
  const assigned = [...new Set((key?.resolver?.default?.onRelease ?? [])
    .filter(a => a.actionID === 'macro.run')
    .map(a => a.arguments?.macro)
    .filter(id => typeof id === 'string'))];
  const list = $('key-macro-assigned');
  list.replaceChildren();
  if (!key || !assigned.length) {
    const empty = document.createElement('li');
    empty.textContent = key ? '割当なし' : 'まずキーを選択';
    list.append(empty);
  }
  for (const id of assigned) {
    const row = document.createElement('li');
    const macro = macros.find(m => m.id === id);
    const name = document.createElement('span');
    name.textContent = macro?.name || '参照先不明のマクロ';
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'action secondary';
    remove.dataset.macroId = id;
    remove.textContent = '外す';
    remove.setAttribute('aria-label', (macro?.name || '参照先不明のマクロ') + 'の割当を外す');
    row.append(name, remove);
    list.append(row);
  }
  const picker = $('key-macro-picker');
  const previous = picker.value;
  picker.replaceChildren();
  const available = macros.filter(m => !assigned.includes(m.id));
  const blank = document.createElement('option');
  blank.value = '';
  blank.textContent = available.length ? 'マクロを選ぶ' : '割当できるマクロなし';
  picker.append(blank);
  for (const m of available) {
    const opt = document.createElement('option');
    opt.value = m.id;
    opt.textContent = m.name || '(名前未設定)';
    picker.append(opt);
  }
  picker.value = available.some(m => m.id === previous) ? previous : '';
  picker.disabled = !key || !available.length;
  $('key-macro-attach').disabled = !key || !picker.value;
  $('key-macro-open-editor').hidden = !!macros.length;
  $('key-macro-guide').textContent = !key
    ? 'キーボードからキーを選択してください。'
    : 'ここでの割当はProfileへの保存用です。実キーボードでの実行は未確認です。';
}
function setSelected(entry) {
  const nextKey = entry ? state.inspected.profile.boardId + '/' + entry.id : null;
  if (state.keyMacroSelection !== nextKey) $('key-macro-feedback').textContent = '';
  if (state.keyEditorSelection !== nextKey) clearKeyEditorFeedback();
  state.keyMacroSelection = nextKey;
  state.keyEditorSelection = nextKey;
  state.selected = entry;
  $('selected-key').textContent = entry
    ? (entry.text || authoredBaseText(state.inspected.profile.boardId, entry.id) || entry.id)
    : 'なし';
  document.querySelectorAll('.key').forEach(key => key.classList.toggle('selected', key.dataset.entryId === entry?.id));
  $('entry-text').disabled = !entry;
  $('apply-key-text').disabled = !entry;
  $('entry-text').value = entry ? authoredBaseText(state.inspected.profile.boardId, entry.id) : '';
  updateTransitionControls(entry);
  updateKeyMacroBindings();
  renderStageEditor();
  renderHoldEditor();
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
  const layer = profile?.layers?.find(item => item.id === state.viewLayerId);
  return !!layer && layer.rootBoardId === state.viewBoardId;
}

function renderBoardPickers() {
  const profile = state.inspected.profile;
  const layers = $('layer-picker');
  const boards = $('board-picker');
  layers.replaceChildren();
  boards.replaceChildren();
  const tabs = $('test-layer-tabs');
  tabs.replaceChildren();
  for (const layer of profile.layers) {
    const option = document.createElement('option');
    option.value = layer.id;
    option.textContent = (layer.name || layer.id) + ' · ' + layer.id;
    layers.append(option);
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'test-layer-choice';
    button.textContent = layer.name || layer.id;
    button.dataset.layerId = layer.id;
    button.setAttribute('aria-pressed', String(layer.id === state.viewLayerId));
    if (layer.id === state.viewLayerId) button.classList.add('active');
    button.addEventListener('click', () => chooseBoard(layer.id, layer.rootBoardId));
    tabs.append(button);
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
    ? 'Rust判定が有効 · タップ／フリックを試せます'
    : '編集専用プレビュー · ここからのジェスチャー再生には非対応';
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
    resetGestureOutcome();
  } catch (error) {
    state.viewLayerId = oldLayer;
    state.viewBoardId = oldBoard;
    status('Boardを表示できません: ' + String(error), true);
    renderBoardPickers();
  }
}

function refreshEditor(snapshot, selectedId = state.selected?.id) {
  let inspected;
  try {
    inspected = inspectSelectedBoard(snapshot.profileJSON);
  } catch (error) {
    // Undo can remove the Stage currently being edited. Restore the closest
    // existing source Board/Key rather than discarding a valid document.
    const restored = JSON.parse(snapshot.profileJSON);
    while (state.stageHistory.length) {
      const prior = state.stageHistory.pop();
      if (!restored.boards.some(board => board.id === prior.boardId)) continue;
      state.viewLayerId = prior.layerId;
      state.viewBoardId = prior.boardId;
      selectedId = prior.entryId;
      inspected = inspectSelectedBoard(snapshot.profileJSON);
      break;
    }
    if (!inspected) {
      state.viewLayerId = null;
      state.viewBoardId = null;
      selectedId = null;
      inspected = inspectSelectedBoard(snapshot.profileJSON);
    }
  }
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
  state.editLocation = null;
  state.testOutput = '';
  renderTestOutput();
  resetGestureOutcome();
  state.stageHistory = [];
  $('stage-feedback').textContent = '';
  clearKeyEditorFeedback();
  state.keyEditorSelection = null;
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
  clearKeyEditorFeedback(); // Clear outcomes invalidated by Undo, Redo or another edit.
  $('stage-feedback').textContent = '';
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
    ? '登録済みアクション ' + m.actions.length + ' 件'
    : 'マクロがありません。名前を入力して新規作成できます。';
  $('macro-internal-id').textContent = m?.id ?? '選択なし';
  $('macro-advanced').hidden = !m;
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
  macroStatus(description + 'しました。');
}
function updateMacroActions(update, label) {
  const m = selectedMacro();
  if (!m) throw new Error('マクロを選択してください');
  const actions = JSON.parse(JSON.stringify(m.actions)); // payload copy, NOT persisted semantics
  update(actions);
  applyCommand({type: 'setMacroActions', macroId: m.id, actions}, label);
  renderMacroEditor();
  macroActionStatus(label + 'しました。');
}

async function saveCurrentDraft() {
  const snapshot = editorSnapshot();
  await writeDraft(snapshot.profileId, snapshot.profileJSON);
  state.savedJSON = snapshot.profileJSON;
  refreshEditor(snapshot);
  status('このブラウザに保存しました。実キーボードには未反映です。');
}

function renderBoard() {
  clearFlickPopup();
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
      // Other Boards are edit-only: let the user inspect the same Rust guide
      // popup without claiming an internal Board gesture was replayed.
      btn.addEventListener('pointerdown', event => {
        if (!event.isPrimary) return;
        showRustGestureGuides(entry);
        showFlickPopup(entry, btn);
      });
      btn.addEventListener('pointerup', clearFlickPopup);
      btn.addEventListener('pointercancel', clearFlickPopup);
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
  gestureOutcome('「' + (entry.text || entry.id) + '」押下中 · 確定判定は指を離した後');
  showRustGestureGuides(entry);
  showFlickPopup(entry, btn);
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
  clearFlickPopup();
  state.activePointer = null;
  const events = a.events;
  // Always advance time in canonical Rust; it alone determines per-entry Hold thresholds.
  if (!cancel) events.push({kind: 'advance', atMs});
  events.push({kind: cancel ? 'cancel' : 'up', atMs});
  const script = {
    layerId: state.viewLayerId,
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
    const outcome = cancel ? 'キャンセル' : (last.terminal || '判定完了');
    const actionText = actions.length ? actions.map(describeRustAction).join('・') : '発行命令なし';
    const inserted = !cancel && last.terminal === 'Committed'
      ? actions.filter(action => ['text.insert', 'text.directInsert'].includes(action.actionID))
        .map(action => action.arguments?.text?.base).filter(text => typeof text === 'string').join('')
      : '';
    if (inserted) {
      state.testOutput = (state.testOutput + inserted).slice(-MAX_TEST_CHARACTERS);
      renderTestOutput();
    }
    if ($('app').dataset.workspace === 'test') {
      if (cancel) {
        gestureOutcome('キャンセルしました。文字は追加されません。');
      } else if (inserted) {
        gestureOutcome('Rust判定で「' + inserted + '」を入力しました。');
      } else if (actions.length) {
        gestureOutcome('Rust判定：' + actionText + '（端末上の操作は実行しません）');
      } else {
        gestureOutcome('Rust判定：' + outcome + ' · 入力された文字はありません。');
      }
    } else {
      gestureOutcome('Rust判定：' + outcome + ' · ' + actionText + '（ブラウザ内）');
    }
    status('Rust判定を実行しました（ブラウザ内のみ）。');
  } catch (error) {
    gestureOutcome('Rust判定エラー：' + String(error?.message || error), true);
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
$('stage-grid').addEventListener('click', event => {
  const cell = event.target.closest('button[data-direction]');
  if (cell && !cell.disabled) editDirection(cell.dataset.direction);
});
$('stage-back').addEventListener('click', returnToPreviousKey);
$('hold-back').addEventListener('click', returnToPreviousKey);
$('hold-open').addEventListener('click', openOrCreateHold);
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
    const result = applyCommand({type: 'setEntryDefaultText', boardId: state.inspected.profile.boardId, entryId: state.selected.id, text: $('entry-text').value}, 'キー文字を変更');
    keyEditorStatus('entry-text-feedback', result.changed ? 'キーの文字を変更しました。' : '文字は変更されていません。');
  } catch(error) { keyEditorStatus('entry-text-feedback', 'キーの文字を変更できません: ' + String(error), true); }
});
$('entry-transition-board').addEventListener('change', event => {
  $('entry-transition-lifetime').disabled = !state.selected || !event.target.value;
});
$('apply-entry-transition').addEventListener('click', () => {
  if (!state.selected) return;
  const target = $('entry-transition-board').value;
  const lifetime = target ? $('entry-transition-lifetime').value : null;
  try {
    const result = applyCommand({
      type: 'setEntryDefaultTransition',
      boardId: state.inspected.profile.boardId,
      entryId: state.selected.id,
      targetBoardId: target || null,
      lifetime
    }, '標準遷移を変更');
    keyEditorStatus('entry-transition-feedback', result.changed ? 'キーの遷移先を変更しました。' : '遷移先は変更されていません。');
  } catch (error) {
    keyEditorStatus('entry-transition-feedback', '遷移先を変更できません: ' + String(error), true);
  }
});

$('key-macro-picker').addEventListener('change', () => {
  $('key-macro-attach').disabled = !$('key-macro-picker').value || !state.selected;
});
$('key-macro-attach').addEventListener('click', () => {
  const entry = state.selected;
  const macroId = $('key-macro-picker').value;
  if (!entry || !macroId) return;
  try {
    const name = state.document?.macros?.find(m => m.id === macroId)?.name || 'マクロ';
    const result = applyCommand({
      type: 'setEntryDefaultMacroInvocation', boardId: state.inspected.profile.boardId,
      entryId: entry.id, macroId, enabled: true
    }, 'マクロ割当');
    keyMacroBindingStatus(result.changed ? name + 'を割り当てました。' : '既に割り当て済みです。');
  } catch (error) {
    keyMacroBindingStatus('割当失敗: ' + String(error), true);
  }
});
$('key-macro-assigned').addEventListener('click', event => {
  const remove = event.target.closest('button[data-macro-id]');
  if (!remove || !state.selected) return;
  const macroId = remove.dataset.macroId;
  const name = state.document?.macros?.find(m => m.id === macroId)?.name || 'マクロ';
  try {
    const result = applyCommand({
      type: 'setEntryDefaultMacroInvocation', boardId: state.inspected.profile.boardId,
      entryId: state.selected.id, macroId, enabled: false
    }, 'マクロ割当解除');
    keyMacroBindingStatus(result.changed ? name + 'の割当を外しました。' : '割当はありません。');
  } catch (error) {
    keyMacroBindingStatus('解除失敗: ' + String(error), true);
  }
});
$('key-macro-open-editor').addEventListener('click', () => {
  $('macro-create-name').focus();
  $('macro-create-name').scrollIntoView({block: 'center'});
});
$('macro-select').addEventListener('change', event => {
  state.macroId = event.target.value;
  state.macroActionIndex = -1;
  renderMacroEditor();
  $('macro-feedback').textContent = '';
});
$('macro-create').addEventListener('click', () => {
  try {
    createMacro($('macro-create-name').value, [], 'マクロを作成');
    $('macro-create-name').value = ''; // Clear only after a successful commit.
  }
  catch (e) { macroStatus('マクロを作成できません: ' + String(e), true); }
});
$('macro-create-sample').addEventListener('click', () => {
  try {
    createMacro('サンプル：あいさつ', [{
      actionID: 'text.insert', arguments: {text: {base: 'こんにちは！', transforms: []}}
    }], 'サンプルMacroを作成');
  } catch (e) { macroStatus('サンプルを作成できません: ' + String(e), true); }
});
$('macro-rename').addEventListener('click', () => {
  const m = selectedMacro();
  if (!m) return;
  try {
    const result = applyCommand({type: 'renameMacro', macroId: m.id, name: $('macro-name').value}, 'マクロ名を変更');
    macroStatus(result.changed ? 'マクロ名を変更しました。' : 'マクロ名は変更されていません。');
  }
  catch (e) { macroStatus('マクロ名を変更できません: ' + String(e), true); }
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
  } catch (e) { macroActionStatus('アクションを追加できません: ' + String(e), true); }
});
$('macro-edit-action').addEventListener('click', () => {
  const m = selectedMacro(), i = state.macroActionIndex;
  if (!m || i < 0 || i >= m.actions.length) return;
  try { updateMacroActions(actions => { actions[i] = actionFromForm(m.actions[i]); }, 'アクションを編集'); }
  catch (e) { macroActionStatus('アクションを編集できません: ' + String(e), true); }
});
$('macro-remove-action').addEventListener('click', () => {
  const m = selectedMacro(), i = state.macroActionIndex;
  if (!m || i < 0 || i >= m.actions.length) return;
  try {
    updateMacroActions(actions => actions.splice(i, 1), 'アクションを削除');
    state.macroActionIndex = -1;
    renderMacroEditor();
  } catch (e) { macroActionStatus('アクションを削除できません: ' + String(e), true); }
});

$('mode-test').addEventListener('click', () => setWorkspaceMode('test'));
$('mode-edit').addEventListener('click', () => setWorkspaceMode('edit'));
$('clear-test-output').addEventListener('click', () => {
  state.testOutput = '';
  renderTestOutput();
  gestureOutcome('入力結果を消しました。次のキーを試せます。');
});
$('layer-picker').addEventListener('change', event => {
  const id = event.target.value;
  const layer = state.inspected.profile.layers.find(item => item.id === id);
  if (layer) {
    state.stageHistory = [];
    chooseBoard(id, layer.rootBoardId);
  }
});
$('board-picker').addEventListener('change', event => {
  state.stageHistory = [];
  chooseBoard(state.viewLayerId, event.target.value);
});
$('build-id').textContent = 'Profile v3 · Rust/Wasm';
boot();
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}
