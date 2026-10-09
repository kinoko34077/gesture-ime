// Browser HostPort: persists Profile drafts only on this device.
// Never forwards edited JSON to a backend or to an OS keyboard.
const NAME = 'gesture-ime-local';
const STORE = 'profiles';

function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(NAME, 1);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(STORE)) {
        request.result.createObjectStore(STORE, {keyPath: 'id'});
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('ブラウザの保存領域が利用できません'));
  });
}

export async function readDraft(id) {
  const db = await open();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readonly');
      const request = tx.objectStore(STORE).get(id);
      let saved = null;
      request.onsuccess = () => { saved = request.result?.json || null; };
      tx.oncomplete = () => resolve(saved);
      tx.onerror = () => reject(tx.error || new Error('読み込み失敗'));
      tx.onabort = () => reject(tx.error || new Error('読み込み中止'));
    });
  } finally { db.close(); }
}

export async function writeDraft(id, json) {
  const db = await open();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite');
      tx.objectStore(STORE).put({id, json});
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error || new Error('保存失敗'));
      tx.onabort = () => reject(tx.error || new Error('保存中止'));
    });
  } finally { db.close(); }
}
