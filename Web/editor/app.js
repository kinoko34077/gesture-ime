// Shared editor-shell foundation. Input semantics come exclusively from Rust Wasm.
const $ = (id) => document.getElementById(id);
const state = { core: null, profileJSON: '', source: '', document: null, inspected: null, selected: null, activePointer: null };
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
function setSelected(entry) {
  state.selected = entry;
  $('selected-key').textContent = entry ? entry.id : 'なし';
  document.querySelectorAll('.key').forEach(key => key.classList.toggle('selected', key.dataset.entryId === entry?.id));
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
    const text = authoredBaseText(profile.initialBoardId, entry.id) || entry.id;
    const label = document.createElement('span');
    label.className = 'key-label';
    label.textContent = text;
    btn.append(label);
    btn.setAttribute('aria-label', 'キー ' + text + '、ID ' + entry.id);
    btn.addEventListener('pointerdown', event => startPointer(event, btn, entry, cols, rows));
    btn.addEventListener('pointermove', updatePointer);
    btn.addEventListener('pointerup', event => finishPointer(event, false));
    btn.addEventListener('pointercancel', event => finishPointer(event, true));
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
  // Simulate elapsed Hold time in the same canonical Rust timing system.
  if (!cancel && atMs >= 480) events.push({kind: 'advance', atMs});
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
function loadProfile(profileJSON, source) {
  // Only the canonical Rust codec can authorize a Profile for the UI.
  const inspected = JSON.parse(state.core.inspect_profile(profileJSON));
  if (!inspected.ok) throw new Error(inspected.error);
  const documentJSON = JSON.parse(profileJSON);
  state.profileJSON = profileJSON;
  state.source = source;
  state.document = documentJSON; // authored base labels only; no condition evaluation in JS
  state.inspected = inspected;
  $('profile-name').textContent = inspected.profile.name + ' · ' + source;
  $('trace-state').textContent = 'キーを押すと結果が表示されます。';
  $('trace-actions').textContent = '—';
  $('export-profile').disabled = false;
  setSelected(null);
  renderBoard();
  status('Profileを検証して読み込みました。');
}
async function builtIn() {
  const response = await fetch('./default-ja.json');
  if (!response.ok) throw new Error('組み込みProfileを取得できません (' + response.status + ')');
  loadProfile(await response.text(), '公開サンプル');
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
    $('rust-status').textContent = 'Rust稼働中';
    await builtIn();
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
    loadProfile(await file.text(), '端末内から読込');
  } catch (error) {
    status('Profileが無効です: ' + String(error?.message || error), true);
  } finally {
    event.target.value = '';
  }
});
$('reset-profile').addEventListener('click', () => builtIn().catch(error => status(String(error), true)));
$('export-profile').addEventListener('click', exportProfile);
$('build-id').textContent = 'Profile v3 · Rust/Wasm';
boot();
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}
