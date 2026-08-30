/* Importazione da CSV, JSON e XLSX.

   Il lettore .xlsx apre il file come archivio ZIP e usa DecompressionStream
   ('deflate-raw'), disponibile in Safari 16.4+ e negli altri browser recenti. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  const DATE_KEYS = ['data', 'date', 'data_estrazione', 'dataestrazione', 'giorno', 'drawdate'];
  const WHEEL_KEYS = ['ruota', 'wheel', 'citta', 'ruota_estrazione'];
  const GAME_KEYS = ['gioco', 'game', 'concorso_tipo', 'tipo'];
  const JOLLY_KEYS = ['jolly', 'numerojolly', 'numero_jolly'];
  const SUPERSTAR_KEYS = ['superstar', 'super_star', 'ss'];
  const COMBINED_KEYS = ['numeri', 'numbers', 'estratti', 'combinazione'];

  function numberKeys(index) {
    return ['numero' + index, 'n' + index, 'num' + index, 'estratto' + index,
      'number' + index, 'n_' + index, 'numero_' + index];
  }

  function normalizeKey(key) {
    return String(key).trim().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/\s+/g, '').replace(/-/g, '_').toLowerCase();
  }

  function firstValue(row, keys) {
    for (let i = 0; i < keys.length; i += 1) {
      const value = row[keys[i]];
      if (value !== undefined && value !== null && String(value).trim() !== '') return String(value);
    }
    return null;
  }

  /** Formati data accettati. Restituisce un timestamp a mezzogiorno UTC. */
  function parseDate(raw) {
    const trimmed = String(raw).trim();
    if (!trimmed) return null;

    let match = trimmed.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
    if (match) return Date.UTC(+match[1], +match[2] - 1, +match[3], 12);

    match = trimmed.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})/);
    if (match) return Date.UTC(+match[3], +match[2] - 1, +match[1], 12);

    match = trimmed.match(/^(\d{4})(\d{2})(\d{2})$/);
    if (match) return Date.UTC(+match[1], +match[2] - 1, +match[3], 12);

    const numeric = Number(trimmed);
    if (isFinite(numeric)) {
      // Timestamp Unix in secondi.
      if (numeric > 100000000) {
        const date = new Date(numeric * 1000);
        return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 12);
      }
      // Numero seriale Excel (giorni dal 30/12/1899).
      if (numeric > 20000 && numeric < 60000) {
        return Date.UTC(1899, 11, 30, 12) + Math.floor(numeric) * 86400000;
      }
    }

    const parsed = Date.parse(trimmed);
    if (!isNaN(parsed)) {
      const date = new Date(parsed);
      return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 12);
    }
    return null;
  }

  function parseGame(raw) {
    const normalized = normalizeKey(raw);
    if (normalized.indexOf('super') >= 0) return 'superenalotto';
    if (normalized.indexOf('lotto') >= 0) return 'lotto';
    return null;
  }

  /** Costruisce un'estrazione da una riga già normalizzata. */
  function recordFromRow(row, defaultGame) {
    const rawDate = firstValue(row, DATE_KEYS);
    if (!rawDate) return null;
    const date = parseDate(rawDate);
    if (date === null) return null;

    const rawGame = firstValue(row, GAME_KEYS);
    const game = (rawGame && parseGame(rawGame)) || defaultGame;
    const info = Lotto.GAMES[game];
    const wheel = Lotto.parseWheel(firstValue(row, WHEEL_KEYS));
    if (info.usesWheels && !wheel) return null;

    let numbers = [];
    for (let index = 1; index <= 6; index += 1) {
      const raw = firstValue(row, numberKeys(index));
      if (raw === null) continue;
      const value = parseInt(raw, 10);
      if (isFinite(value) && value >= 1 && value <= 90) numbers.push(value);
    }
    if (!numbers.length) {
      const combined = firstValue(row, COMBINED_KEYS);
      if (combined) {
        numbers = combined.split(/[\s,;|.-]+/)
          .map((part) => parseInt(part, 10))
          .filter((value) => isFinite(value) && value >= 1 && value <= 90);
      }
    }
    if (numbers.length < info.drawnCount) return null;
    numbers = numbers.slice(0, info.drawnCount);

    const jollyRaw = firstValue(row, JOLLY_KEYS);
    const superRaw = firstValue(row, SUPERSTAR_KEYS);
    return Lotto.makeDraw(date, game, info.usesWheels ? wheel : null, numbers,
      info.usesJolly && jollyRaw ? parseInt(jollyRaw, 10) : null,
      info.usesSuperStar && superRaw ? parseInt(superRaw, 10) : null);
  }

  // ------------------------------------------------------------------ CSV

  function detectSeparator(text) {
    const firstLine = text.split('\n', 1)[0] || '';
    const candidates = [';', ',', '\t', '|'];
    let best = ',';
    let bestCount = 0;
    candidates.forEach((candidate) => {
      const count = firstLine.split(candidate).length - 1;
      if (count > bestCount) { best = candidate; bestCount = count; }
    });
    return best;
  }

  /** Parser CSV conforme a RFC 4180: virgolette doppie e campi multilinea. */
  function parseCSVRows(text, separator) {
    const rows = [];
    let row = [];
    let field = '';
    let insideQuotes = false;
    let index = 0;

    function finishField() { row.push(field.trim()); field = ''; }
    function finishRow() {
      finishField();
      if (row.some((value) => value !== '')) rows.push(row);
      row = [];
    }

    while (index < text.length) {
      const character = text[index];
      if (insideQuotes) {
        if (character === '"') {
          if (text[index + 1] === '"') { field += '"'; index += 2; continue; }
          insideQuotes = false;
          index += 1;
          continue;
        }
        field += character;
        index += 1;
        continue;
      }
      if (character === '"') { insideQuotes = true; index += 1; continue; }
      if (character === separator) { finishField(); index += 1; continue; }
      if (character === '\n') { finishRow(); index += 1; continue; }
      if (character === '\r') { index += 1; continue; }
      field += character;
      index += 1;
    }
    if (field !== '' || row.length) finishRow();
    return rows;
  }

  function parseCSV(text, defaultGame) {
    const separator = detectSeparator(text);
    const rows = parseCSVRows(text, separator);
    if (rows.length < 2) throw new Error('Il file non contiene righe valide.');
    const keys = rows[0].map(normalizeKey);
    const records = [];
    for (let r = 1; r < rows.length; r += 1) {
      const row = {};
      for (let c = 0; c < keys.length && c < rows[r].length; c += 1) row[keys[c]] = rows[r][c];
      const record = recordFromRow(row, defaultGame);
      if (record) records.push(record);
    }
    if (!records.length) throw new Error('Nessuna estrazione riconosciuta nel file. Controlla le colonne obbligatorie: data, ruota, numeri.');
    return records;
  }

  // ----------------------------------------------------------------- JSON

  function flatten(object, prefix, target) {
    Object.keys(object).forEach((key) => {
      const value = object[key];
      const normalized = normalizeKey(prefix ? prefix + '_' + key : key);
      if (Array.isArray(value)) {
        const values = value.map((item) => parseInt(item, 10)).filter((item) => isFinite(item));
        target[normalized] = value.join(',');
        values.slice(0, 6).forEach((item, index) => { target['numero' + (index + 1)] = String(item); });
      } else if (value && typeof value === 'object') {
        flatten(value, key, target);
      } else if (value !== null && value !== undefined) {
        target[normalized] = String(value);
      }
    });
    return target;
  }

  function parseJSON(text, defaultGame) {
    const parsed = JSON.parse(text);
    let array = null;
    if (Array.isArray(parsed)) {
      array = parsed;
    } else if (parsed && typeof parsed === 'object') {
      const keys = ['draws', 'estrazioni', 'data', 'results', 'items', 'records'];
      for (let i = 0; i < keys.length && !array; i += 1) {
        if (Array.isArray(parsed[keys[i]])) array = parsed[keys[i]];
      }
      if (!array) {
        Object.keys(parsed).forEach((key) => {
          if (!array && Array.isArray(parsed[key]) && parsed[key].length) array = parsed[key];
        });
      }
    }
    if (!array) throw new Error('Struttura JSON non riconosciuta.');
    const records = [];
    array.forEach((element) => {
      if (!element || typeof element !== 'object') return;
      const record = recordFromRow(flatten(element, '', {}), defaultGame);
      if (record) records.push(record);
    });
    if (!records.length) throw new Error('Nessuna estrazione riconosciuta nel JSON.');
    return records;
  }

  // ----------------------------------------------------------------- XLSX

  function readUInt16(view, offset) { return view.getUint16(offset, true); }
  function readUInt32(view, offset) { return view.getUint32(offset, true); }

  /** Legge le voci di un archivio ZIP (solo quanto serve per un .xlsx). */
  function readZipEntries(buffer) {
    const view = new DataView(buffer);
    const length = buffer.byteLength;
    let end = -1;
    const lowerBound = Math.max(0, length - 22 - 65535);
    for (let offset = length - 22; offset >= lowerBound; offset -= 1) {
      if (readUInt32(view, offset) === 0x06054b50) { end = offset; break; }
    }
    if (end < 0) throw new Error('File Excel non valido (archivio ZIP non riconosciuto).');

    const entryCount = readUInt16(view, end + 10);
    let cursor = readUInt32(view, end + 16);
    const entries = [];
    for (let i = 0; i < entryCount; i += 1) {
      if (cursor + 46 > length || readUInt32(view, cursor) !== 0x02014b50) break;
      const method = readUInt16(view, cursor + 10);
      const compressedSize = readUInt32(view, cursor + 20);
      const uncompressedSize = readUInt32(view, cursor + 24);
      const nameLength = readUInt16(view, cursor + 28);
      const extraLength = readUInt16(view, cursor + 30);
      const commentLength = readUInt16(view, cursor + 32);
      const localOffset = readUInt32(view, cursor + 42);
      const name = new TextDecoder().decode(new Uint8Array(buffer, cursor + 46, nameLength));
      entries.push({ name, method, compressedSize, uncompressedSize, localOffset });
      cursor += 46 + nameLength + extraLength + commentLength;
    }
    return { view, entries };
  }

  function extractEntry(buffer, archive, name) {
    const entry = archive.entries.find((item) => item.name === name);
    if (!entry) return Promise.resolve(null);
    const view = archive.view;
    if (readUInt32(view, entry.localOffset) !== 0x04034b50) return Promise.resolve(null);
    const nameLength = readUInt16(view, entry.localOffset + 26);
    const extraLength = readUInt16(view, entry.localOffset + 28);
    const start = entry.localOffset + 30 + nameLength + extraLength;
    const payload = new Uint8Array(buffer, start, entry.compressedSize);

    if (entry.method === 0) return Promise.resolve(new TextDecoder().decode(payload));
    if (entry.method !== 8) return Promise.reject(new Error('Compressione ZIP non supportata.'));
    if (typeof DecompressionStream === 'undefined') {
      return Promise.reject(new Error('Questo browser non sa decomprimere i file .xlsx. Converti il file in CSV.'));
    }
    const stream = new Blob([payload]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    return new Response(stream).text();
  }

  /** Indice di colonna 0-based da un riferimento di cella ("BC12"). */
  function columnIndex(reference) {
    let index = 0;
    for (let i = 0; i < reference.length; i += 1) {
      const code = reference.charCodeAt(i);
      if (code >= 65 && code <= 90) index = index * 26 + (code - 64);
      else if (code >= 97 && code <= 122) index = index * 26 + (code - 96);
      else break;
    }
    return Math.max(index - 1, 0);
  }

  function parseSharedStrings(xml) {
    if (!xml) return [];
    const parser = new DOMParser().parseFromString(xml, 'application/xml');
    return Array.from(parser.getElementsByTagName('si')).map((node) => {
      return Array.from(node.getElementsByTagName('t')).map((t) => t.textContent).join('');
    });
  }

  function parseSheet(xml, sharedStrings) {
    const parser = new DOMParser().parseFromString(xml, 'application/xml');
    return Array.from(parser.getElementsByTagName('row')).map((rowNode) => {
      const cells = [];
      Array.from(rowNode.getElementsByTagName('c')).forEach((cell) => {
        const reference = cell.getAttribute('r') || '';
        const type = cell.getAttribute('t');
        const valueNode = cell.getElementsByTagName('v')[0];
        let value = valueNode ? valueNode.textContent : '';
        if (type === 's') {
          const index = parseInt(value, 10);
          value = sharedStrings[index] !== undefined ? sharedStrings[index] : '';
        } else if (type === 'inlineStr') {
          value = Array.from(cell.getElementsByTagName('t')).map((t) => t.textContent).join('');
        }
        const target = columnIndex(reference);
        while (cells.length < target) cells.push('');
        cells.push(value);
      });
      return cells;
    }).filter((cells) => cells.some((value) => value !== ''));
  }

  function parseXLSX(buffer, defaultGame) {
    const archive = readZipEntries(buffer);
    const sheetName = archive.entries
      .map((entry) => entry.name)
      .filter((name) => name.indexOf('xl/worksheets/sheet') === 0 && name.slice(-4) === '.xml')
      .sort()[0] || 'xl/worksheets/sheet1.xml';

    return extractEntry(buffer, archive, 'xl/sharedStrings.xml')
      .catch(() => null)
      .then((sharedXml) => {
        const sharedStrings = parseSharedStrings(sharedXml);
        return extractEntry(buffer, archive, sheetName).then((sheetXml) => {
          if (!sheetXml) throw new Error('Foglio di calcolo non leggibile.');
          const rows = parseSheet(sheetXml, sharedStrings);
          if (rows.length < 2) throw new Error('Il foglio non contiene righe valide.');
          const keys = rows[0].map(normalizeKey);
          const records = [];
          for (let r = 1; r < rows.length; r += 1) {
            const row = {};
            for (let c = 0; c < keys.length && c < rows[r].length; c += 1) {
              if (keys[c]) row[keys[c]] = rows[r][c];
            }
            const record = recordFromRow(row, defaultGame);
            if (record) records.push(record);
          }
          if (!records.length) throw new Error('Nessuna estrazione riconosciuta nel file Excel.');
          return records;
        });
      });
  }

  // ----------------------------------------------------------- Coordinatore

  /** Riconosce il formato dall'estensione o dal contenuto e importa il file. */
  function importFile(file, defaultGame) {
    const name = (file.name || '').toLowerCase();
    const extension = name.indexOf('.') >= 0 ? name.split('.').pop() : '';

    if (extension === 'xlsx' || extension === 'xlsm') {
      return file.arrayBuffer().then((buffer) => parseXLSX(buffer, defaultGame));
    }
    if (extension === 'xls') {
      return Promise.reject(new Error('I file .xls binari non sono supportati: convertili in .xlsx o .csv.'));
    }
    return file.arrayBuffer().then((buffer) => {
      const bytes = new Uint8Array(buffer);
      // "PK": archivio ZIP, quindi xlsx anche senza estensione.
      if (bytes.length > 1 && bytes[0] === 0x50 && bytes[1] === 0x4b) {
        return parseXLSX(buffer, defaultGame);
      }
      let text;
      try {
        text = new TextDecoder('utf-8', { fatal: false }).decode(buffer);
      } catch (error) {
        text = new TextDecoder('windows-1252').decode(buffer);
      }
      const trimmed = text.trim();
      if (trimmed.charAt(0) === '{' || trimmed.charAt(0) === '[') return parseJSON(text, defaultGame);
      return parseCSV(text, defaultGame);
    });
  }

  /** Scarica ed importa da una sorgente remota configurata dall'utente. */
  function importFromURL(url, defaultGame) {
    return fetch(url, { cache: 'no-store' }).then((response) => {
      if (!response.ok) throw new Error('Risposta HTTP ' + response.status);
      const contentType = (response.headers.get('Content-Type') || '').toLowerCase();
      if (contentType.indexOf('json') >= 0) return response.text().then((text) => parseJSON(text, defaultGame));
      if (contentType.indexOf('spreadsheet') >= 0 || contentType.indexOf('excel') >= 0) {
        return response.arrayBuffer().then((buffer) => parseXLSX(buffer, defaultGame));
      }
      return response.arrayBuffer().then((buffer) => {
        const bytes = new Uint8Array(buffer);
        if (bytes.length > 1 && bytes[0] === 0x50 && bytes[1] === 0x4b) return parseXLSX(buffer, defaultGame);
        const text = new TextDecoder().decode(buffer);
        const trimmed = text.trim();
        if (trimmed.charAt(0) === '{' || trimmed.charAt(0) === '[') return parseJSON(text, defaultGame);
        return parseCSV(text, defaultGame);
      });
    });
  }

  Lotto.importer = {
    normalizeKey: normalizeKey,
    parseDate: parseDate,
    parseCSV: parseCSV,
    parseCSVRows: parseCSVRows,
    detectSeparator: detectSeparator,
    parseJSON: parseJSON,
    parseXLSX: parseXLSX,
    recordFromRow: recordFromRow,
    importFile: importFile,
    importFromURL: importFromURL
  };
})(typeof self !== 'undefined' ? self : this);
