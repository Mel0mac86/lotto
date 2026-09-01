/* Esito della caccia sistematica ai pattern su tutto lo storico.

   Il file data/pattern-lotto.json è prodotto da tools/cerca_pattern.py: 48 test
   decisi in anticipo su 77.000 estrazioni, con correzione di Benjamini-Hochberg
   per la molteplicità. Va calcolato fuori dal telefono perché guarda l'archivio
   intero, non il periodo selezionato dall'utente. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const FILE = 'data/pattern-lotto.json';

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

  Lotto.patternArchive = { file: FILE, load: load };
})(typeof self !== 'undefined' ? self : this);
