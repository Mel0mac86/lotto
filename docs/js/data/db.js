/* Archivio locale su IndexedDB.

   I dati restano sul dispositivo: nessun account, nessuna sincronizzazione,
   nessun invio. Le estrazioni sono in un archivio separato dalle preferenze. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const DB_NAME = 'lotto-ai-analyzer';
  const DB_VERSION = 2;
  const STORE_DRAWS = 'draws';
  const STORE_SAVED = 'saved';

  /* Le estrazioni non stanno una per riga: sono raggruppate in blocchi
     gioco|ruota|anno, poche centinaia in tutto.

     Con una riga per estrazione, scrivere i 77.000 record dello storico
     ufficiale del Lotto richiedeva oltre un minuto e rileggerli quasi due
     secondi; a blocchi la scrittura sta sotto il secondo e la lettura sotto il
     decimo di secondo. La differenza la fa il numero di scritture, non il
     volume dei dati. */

  let database = null;

  function open() {
    if (database) return Promise.resolve(database);
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        // La versione 1 teneva una riga per estrazione: qui l'archivio si ricrea
        // a blocchi. Le estrazioni si ricaricano dallo storico incluso o dai file.
        if (db.objectStoreNames.contains(STORE_DRAWS) && event.oldVersion < 2) {
          db.deleteObjectStore(STORE_DRAWS);
        }
        if (!db.objectStoreNames.contains(STORE_DRAWS)) {
          const store = db.createObjectStore(STORE_DRAWS, { keyPath: 'id' });
          store.createIndex('game', 'game', { unique: false });
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

  function blockYear(timestamp) {
    // Le date sono normalizzate a mezzogiorno UTC: l'anno UTC è quello giusto.
    return new Date(timestamp).getUTCFullYear();
  }

  function blockId(game, wheel, year) {
    return game + '|' + (wheel || '-') + '|' + year;
  }

  /** Chiave interna al blocco: gioco, ruota e anno li fissa già il blocco. */
  function entryKey(date, numbers) {
    return date + '|' + numbers.join('-');
  }

  function expandBlocks(blocks) {
    const draws = [];
    blocks.forEach((block) => {
      block.draws.forEach((entry) => {
        draws.push(Lotto.makeDraw(entry.d, block.game, block.wheel, entry.n,
          entry.j === undefined ? null : entry.j,
          entry.s === undefined ? null : entry.s));
      });
    });
    return draws.sort((a, b) => a.date - b.date);
  }

  function blocksOfGame(gameId) {
    return transaction(STORE_DRAWS, 'readonly')
      .then((store) => requestToPromise(store.index('game').getAll(gameId)));
  }

  /** Tutte le estrazioni di un gioco, ordinate per data crescente. */
  function loadDraws(gameId) {
    return blocksOfGame(gameId).then(expandBlocks);
  }

  function loadAllDraws() {
    return transaction(STORE_DRAWS, 'readonly')
      .then((store) => requestToPromise(store.getAll()))
      .then(expandBlocks);
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

  // Blocchi riscritti per transazione. Con lo storico completo del Lotto sono
  // circa novecento blocchi in tutto, quindi bastano pochi giri.
  const BLOCKS_PER_TRANSACTION = 150;

  /**
   * Inserisce le estrazioni scartando i duplicati.
   *
   * `onProgress` riceve { done, total } contati in blocchi scritti: serve alle
   * importazioni lunghe per mostrare l'avanzamento.
   */
  function insertDraws(records, source, onProgress) {
    const result = { inserted: 0, duplicates: 0, rejected: 0, errors: [] };
    const groups = new Map();

    records.forEach((record) => {
      if (!isValid(record)) { result.rejected += 1; return; }
      const id = blockId(record.game, record.wheel, blockYear(record.date));
      let list = groups.get(id);
      if (!list) { list = []; groups.set(id, list); }
      list.push(record);
    });

    const ids = Array.from(groups.keys());
    if (!ids.length) return Promise.resolve(result);

    return open().then((db) => {
      let offset = 0;

      function writeSlice() {
        if (offset >= ids.length) return Promise.resolve(result);
        const slice = ids.slice(offset, offset + BLOCKS_PER_TRANSACTION);
        offset += slice.length;

        return new Promise((resolve, reject) => {
          const tx = db.transaction(STORE_DRAWS, 'readwrite');
          const store = tx.objectStore(STORE_DRAWS);

          slice.forEach((id) => {
            const request = store.get(id);
            request.onsuccess = () => {
              const incoming = groups.get(id);
              const block = request.result || {
                id: id,
                game: incoming[0].game,
                wheel: incoming[0].wheel,
                year: blockYear(incoming[0].date),
                draws: []
              };
              const known = new Set(block.draws.map((entry) => entryKey(entry.d, entry.n)));
              incoming.forEach((record) => {
                const key = entryKey(record.date, record.numbers);
                if (known.has(key)) { result.duplicates += 1; return; }
                known.add(key);
                block.draws.push({
                  d: record.date, n: record.numbers,
                  j: record.jolly, s: record.superstar
                });
                result.inserted += 1;
              });
              block.draws.sort((a, b) => a.d - b.d);
              block.source = source || block.source || 'import';
              block.updatedAt = Date.now();
              store.put(block);
            };
          });

          tx.oncomplete = () => resolve();
          tx.onerror = () => reject(tx.error);
          tx.onabort = () => reject(tx.error || new Error('Scrittura interrotta.'));
        }).then(() => {
          if (onProgress) onProgress({ done: offset, total: ids.length });
          return writeSlice();
        });
      }

      return writeSlice();
    });
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
