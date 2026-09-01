/* Previsioni di TimesFM 3.0 e misura di quanto valgono.

   TimesFM è il modello di forecasting per serie temporali di Google Research:
   è un transformer da oltre un miliardo di parametri, gira in Python su
   PyTorch e non può girare dentro il browser. Le previsioni sono quindi
   calcolate una volta sola dagli script in tools/ e distribuite come file.

   Il file contiene sempre due cose insieme: i numeri previsti e la misura,
   walk-forward, di quanto quei numeri valgano. L'app non mostra mai le prime
   senza la seconda. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const FILE = 'data/timesfm-previsioni.json';

  let promise = null;

  function load() {
    if (!promise) {
      promise = fetch(FILE, { cache: 'default' })
        .then((response) => {
          if (!response.ok) throw new Error('HTTP ' + response.status);
          return response.json();
        })
        .catch(() => null);
    }
    return promise;
  }

  /** La riga della valutazione con il risultato migliore fra le codifiche. */
  function bestRow(rows) {
    if (!rows || !rows.length) return null;
    return rows.reduce((best, row) => {
      if (row.nome.indexOf('TimesFM') !== 0) return best;
      if (!best || row.centriPerEstrazione > best.centriPerEstrazione) return row;
      return best;
    }, null);
  }

  function baselineRow(rows) {
    return (rows || []).find((row) => row.nome.indexOf('5 numeri a caso') >= 0) || null;
  }

  Lotto.timesfm = {
    file: FILE,
    load: load,
    bestRow: bestRow,
    baselineRow: baselineRow
  };
})(typeof self !== 'undefined' ? self : this);
