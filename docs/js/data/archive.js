/* Storico ufficiale distribuito insieme all'app.

   Le estrazioni non le deve più cercare l'utente: i file sotto data/ sono già
   nel pacchetto e vengono caricati con un tocco. Restano comunque semplici
   CSV, quindi sono leggibili e reimportabili anche a mano.

   Provenienza e data di aggiornamento sono in data/manifest.json e ripetute
   nella schermata Dati: chi usa l'app deve poter risalire alla fonte. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  const FILES = {
    lotto: 'data/lotto-storico.csv',
    superenalotto: 'data/superenalotto-storico.csv'
  };

  const MANIFEST_FILE = 'data/manifest.json';

  let manifestPromise = null;

  /** Il manifesto è piccolo: si legge all'avvio per descrivere l'archivio
      senza scaricare i due megabyte del CSV.

      `fresh` salta la cache: serve al controllo degli aggiornamenti, che deve
      vedere il manifesto appena pubblicato e non la copia del service worker. */
  function loadManifest(fresh) {
    if (fresh) {
      manifestPromise = fetch(MANIFEST_FILE, { cache: 'no-store' })
        .then((response) => {
          if (!response.ok) throw new Error('HTTP ' + response.status);
          return response.json();
        })
        .catch(() => null);
      return manifestPromise;
    }
    if (!manifestPromise) {
      manifestPromise = fetch(MANIFEST_FILE, { cache: 'default' })
        .then((response) => {
          if (!response.ok) throw new Error('HTTP ' + response.status);
          return response.json();
        })
        .catch(() => null);
    }
    return manifestPromise;
  }

  /** Data italiana gg/mm/aaaa del manifesto, come istante confrontabile. */
  function timestampFromItalianDate(value) {
    const parts = String(value || '').split('/');
    if (parts.length !== 3) return null;
    const stamp = Date.UTC(+parts[2], +parts[1] - 1, +parts[0], 12);
    return isFinite(stamp) ? stamp : null;
  }

  /**
   * Controlla se il pacchetto contiene estrazioni più recenti di quelle in
   * archivio e, se sì, le importa.
   *
   * Il confronto è fra la data dell'ultima estrazione che l'app ha già e quella
   * dichiarata dal manifesto: scarica il CSV solo quando c'è davvero qualcosa
   * di nuovo. I duplicati vengono comunque ignorati in fase di inserimento,
   * quindi un doppio controllo non fa danni.
   */
  function checkForUpdates(latestByGame, onProgress) {
    return loadManifest(true).then((manifest) => {
      if (!manifest || !manifest.archives) return null;

      const stale = Object.keys(manifest.archives).filter((gameId) => {
        const published = timestampFromItalianDate(manifest.archives[gameId].lastDate);
        if (published === null) return false;
        const owned = latestByGame[gameId];
        // Nessuna estrazione in archivio: non è un aggiornamento, è un primo
        // caricamento, e quello lo decide l'utente.
        return owned ? published > owned : false;
      });

      if (!stale.length) return { updated: [], manifest: manifest };

      return stale.reduce((chain, gameId) => chain.then((results) =>
        loadArchive(gameId, onProgress).then((result) => {
          results.push({ game: gameId, inserted: result.inserted,
            lastDate: manifest.archives[gameId].lastDate });
          return results;
        })), Promise.resolve([]))
        .then((results) => ({
          updated: results.filter((item) => item.inserted > 0),
          manifest: manifest
        }));
    });
  }

  function timestampFromCompactDate(value) {
    // Formato aaaammgg, l'unico usato nei file inclusi.
    const year = +value.slice(0, 4);
    const month = +value.slice(4, 6);
    const day = +value.slice(6, 8);
    if (!isFinite(year) || !isFinite(month) || !isFinite(day)) return null;
    return Date.UTC(year, month - 1, day, 12);
  }

  function optionalNumber(raw) {
    if (raw === undefined) return null;
    const trimmed = raw.trim();
    if (!trimmed) return null;
    const value = +trimmed;
    return isFinite(value) && value >= 1 && value <= 90 ? value : null;
  }

  /** Lettura veloce dei CSV inclusi: il tracciato è noto e fisso, quindi
      non serve il parser generico di Lotto.importer. */
  function parseArchive(text, gameId) {
    const lines = text.split('\n');
    const records = [];
    const wheelCache = {};
    const superenalotto = gameId === 'superenalotto';

    for (let index = 1; index < lines.length; index += 1) {
      // I file inclusi hanno terminatori Unix, ma un CSV rigenerato altrove
      // potrebbe portarsi dietro il ritorno a capo di Windows.
      const line = lines[index].charCodeAt(lines[index].length - 1) === 13
        ? lines[index].slice(0, -1) : lines[index];
      if (!line) continue;
      const parts = line.split(';');
      if (parts.length < (superenalotto ? 8 : 7)) continue;

      const date = timestampFromCompactDate(parts[0]);
      if (date === null) continue;

      if (superenalotto) {
        // data;concorso;numero1..numero6;jolly;superstar
        const numbers = [];
        for (let n = 2; n <= 7; n += 1) numbers.push(+parts[n]);
        const jolly = optionalNumber(parts[8]);
        const superstar = optionalNumber(parts[9]);
        records.push(Lotto.makeDraw(date, 'superenalotto', null, numbers, jolly, superstar));
      } else {
        // data;ruota;numero1..numero5
        const code = parts[1];
        let wheel = wheelCache[code];
        if (wheel === undefined) {
          wheel = wheelCache[code] = Lotto.parseWheel(code);
        }
        if (!wheel) continue;
        records.push(Lotto.makeDraw(date, 'lotto', wheel,
          [+parts[2], +parts[3], +parts[4], +parts[5], +parts[6]], null, null));
      }
    }
    return records;
  }

  /** Scarica il file incluso, lo legge e lo archivia in IndexedDB. */
  function loadArchive(gameId, onProgress) {
    const file = FILES[gameId];
    if (!file) return Promise.reject(new Error('Nessuno storico incluso per questo gioco.'));

    if (onProgress) onProgress({ phase: 'download', done: 0, total: 1 });
    return fetch(file, { cache: 'default' })
      .then((response) => {
        if (!response.ok) throw new Error('Storico non raggiungibile (HTTP ' + response.status + ').');
        return response.text();
      })
      .then((text) => {
        if (onProgress) onProgress({ phase: 'parse', done: 0, total: 1 });
        const records = parseArchive(text, gameId);
        if (!records.length) throw new Error('Il file dello storico è vuoto o illeggibile.');
        return Lotto.db.insertDraws(records, 'storico ufficiale', (written) => {
          if (onProgress) {
            onProgress({ phase: 'insert', done: written.done, total: written.total });
          }
        });
      });
  }

  Lotto.archive = {
    files: FILES,
    loadManifest: loadManifest,
    loadArchive: loadArchive,
    checkForUpdates: checkForUpdates,
    parseArchive: parseArchive
  };
})(typeof self !== 'undefined' ? self : this);
