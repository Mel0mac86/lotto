/* Archivio locale su IndexedDB.

   I dati restano sul dispositivo: nessun account, nessuna sincronizzazione,
   nessun invio. Le estrazioni sono in un archivio separato dalle preferenze. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const DB_NAME = 'lotto-ai-analyzer';
  const DB_VERSION = 1;
  const STORE_DRAWS = 'draws';
  const STORE_SAVED = 'saved';

  let database = null;

  function open() {
    if (database) return Promise.resolve(database);
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains(STORE_DRAWS)) {
          const store = db.createObjectStore(STORE_DRAWS, { keyPath: 'key' });
          store.createIndex('game', 'game', { unique: false });
          store.createIndex('date', 'date', { unique: false });
        }
        if (!db.objectStoreNames.contains(STORE_SAVED)) {
          db.createObjectStore(STORE_SAVED, { keyPath: 'id' });
        }
      };
      request.onsuccess = () => { database = request.result; resolve(database); };
      request.onerror = () => reject(request.error || new Error('Impossibile aprire l’archivio locale.'));
    });
  }

  function transaction(storeName, mode) {
    return open().then((db) => db.transaction(storeName, mode).objectStore(storeName));
  }

  function requestToPromise(request) {
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  /** Tutte le estrazioni di un gioco, ordinate per data crescente. */
  function loadDraws(gameId) {
    return transaction(STORE_DRAWS, 'readonly')
      .then((store) => requestToPromise(store.index('game').getAll(gameId)))
      .then((rows) => rows
        .map((row) => Lotto.makeDraw(row.date, row.game, row.wheel, row.numbers, row.jolly, row.superstar))
        .sort((a, b) => a.date - b.date));
  }

  function loadAllDraws() {
    return transaction(STORE_DRAWS, 'readonly')
      .then((store) => requestToPromise(store.getAll()))
      .then((rows) => rows
        .map((row) => Lotto.makeDraw(row.date, row.game, row.wheel, row.numbers, row.jolly, row.superstar))
        .sort((a, b) => a.date - b.date));
  }

  function countDraws(gameId) {
    return transaction(STORE_DRAWS, 'readonly')
      .then((store) => requestToPromise(store.index('game').count(gameId)));
  }

  /** Valida un'estrazione prima dell'inserimento. */
  function isValid(draw) {
    const game = Lotto.GAMES[draw.game];
    if (!game) return false;
    if (draw.numbers.length !== game.drawnCount) return false;
    if (new Set(draw.numbers).size !== draw.numbers.length) return false;
    if (!draw.numbers.every((n) => n >= 1 && n <= 90)) return false;
    if (game.usesWheels && !draw.wheel) return false;
    if (draw.jolly !== null && (draw.jolly < 1 || draw.jolly > 90)) return false;
    if (draw.superstar !== null && (draw.superstar < 1 || draw.superstar > 90)) return false;
    return isFinite(draw.date);
  }

  /** Inserisce le estrazioni scartando i duplicati. */
  function insertDraws(records, source) {
    const result = { inserted: 0, duplicates: 0, rejected: 0, errors: [] };
    return open().then((db) => new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_DRAWS, 'readwrite');
      const store = tx.objectStore(STORE_DRAWS);
      const seen = new Set();

      records.forEach((record) => {
        if (!isValid(record)) { result.rejected += 1; return; }
        const key = Lotto.dedupeKey(record);
        if (seen.has(key)) { result.duplicates += 1; return; }
        seen.add(key);
        const row = {
          key: key,
          date: record.date,
          game: record.game,
          wheel: record.wheel,
          numbers: record.numbers,
          jolly: record.jolly,
          superstar: record.superstar,
          source: source || 'import',
          importedAt: Date.now()
        };
        const request = store.add(row);
        request.onsuccess = () => { result.inserted += 1; };
        // Chiave già presente: è un duplicato, non un errore.
        request.onerror = (event) => { result.duplicates += 1; event.preventDefault(); };
      });

      tx.oncomplete = () => resolve(result);
      tx.onerror = () => reject(tx.error);
    }));
  }

  function deleteGame(gameId) {
    return open().then((db) => new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_DRAWS, 'readwrite');
      const store = tx.objectStore(STORE_DRAWS);
      const request = store.index('game').openKeyCursor(IDBKeyRange.only(gameId));
      request.onsuccess = (event) => {
        const cursor = event.target.result;
        if (cursor) { store.delete(cursor.primaryKey); cursor.continue(); }
      };
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    }));
  }

  // ------------------------------------------------ Combinazioni salvate

  function saveCombination(entry) {
    const row = Object.assign({ id: 'c-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8) }, entry);
    return transaction(STORE_SAVED, 'readwrite').then((store) => requestToPromise(store.add(row))).then(() => row);
  }

  function loadSavedCombinations() {
    return transaction(STORE_SAVED, 'readonly')
      .then((store) => requestToPromise(store.getAll()))
      .then((rows) => rows.sort((a, b) => b.createdAt - a.createdAt));
  }

  function deleteSavedCombination(id) {
    return transaction(STORE_SAVED, 'readwrite').then((store) => requestToPromise(store.delete(id)));
  }

  // ------------------------------------------------------- Impostazioni

  const SETTINGS_KEY = 'lotto.settings.v1';

  const DEFAULT_SETTINGS = {
    weights: Lotto.WEIGHT_PRESETS.balanced,
    defaultGame: 'lotto',
    defaultWheel: 'Bari',
    defaultPeriod: 'fiveYears',
    theme: 'system',
    payouts: { lotto: Object.assign({}, Lotto.PAYOUTS ? Lotto.PAYOUTS.lotto : {}), superenalotto: {} },
    acceptedDisclaimer: false
  };

  function loadSettings() {
    try {
      const raw = localStorage.getItem(SETTINGS_KEY);
      if (!raw) return Object.assign({}, DEFAULT_SETTINGS);
      return Object.assign({}, DEFAULT_SETTINGS, JSON.parse(raw));
    } catch (error) {
      return Object.assign({}, DEFAULT_SETTINGS);
    }
  }

  function saveSettings(settings) {
    try {
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
    } catch (error) {
      // Spazio esaurito o modalità privata: le impostazioni restano valide per la sessione.
    }
  }

  Lotto.db = {
    loadDraws: loadDraws,
    loadAllDraws: loadAllDraws,
    countDraws: countDraws,
    insertDraws: insertDraws,
    deleteGame: deleteGame,
    saveCombination: saveCombination,
    loadSavedCombinations: loadSavedCombinations,
    deleteSavedCombination: deleteSavedCombination,
    loadSettings: loadSettings,
    saveSettings: saveSettings,
    DEFAULT_SETTINGS: DEFAULT_SETTINGS
  };
})(typeof self !== 'undefined' ? self : this);
