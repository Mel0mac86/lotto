/* Schermata Dati: archivio, importazione, sorgenti remote, preferenze
   dello scoring e informazioni sulla privacy. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const ui = Lotto.ui;
  const el = ui.el;
  const views = Lotto.views = Lotto.views || {};

  views.data = function () {
    let importGame = Lotto.app.state.settings.defaultGame;
    let lastResult = null;
    let busy = false;

    function reload() {
      return Lotto.app.syncDraws().then(() => Lotto.app.refresh());
    }

    function handleFiles(files) {
      if (!files || !files.length) return;
      busy = true;
      Lotto.app.refresh();
      const totals = { inserted: 0, duplicates: 0, rejected: 0, errors: [] };

      const chain = Array.prototype.slice.call(files).reduce((promise, file) => promise
        .then(() => Lotto.importer.importFile(file, importGame))
        .then((records) => Lotto.db.insertDraws(records, file.name))
        .then((result) => {
          totals.inserted += result.inserted;
          totals.duplicates += result.duplicates;
          totals.rejected += result.rejected;
        })
        .catch((error) => { totals.errors.push(file.name + ': ' + error.message); }),
      Promise.resolve());

      chain.then(() => {
        lastResult = totals;
        busy = false;
        return reload();
      });
    }

    return {
      title: 'Dati',
      render: function (container) {
        const state = Lotto.app.state;

        // --- Archivio
        const archive = el('div.rows');
        Object.keys(Lotto.GAMES).forEach((gameId) => {
          const game = Lotto.GAMES[gameId];
          archive.appendChild(el('div.row', {}, [
            el('span.grow', {}, [
              el('div', { text: game.symbol + ' ' + game.name, style: { fontWeight: '500' } }),
              el('div.note', { text: state.latest[gameId]
                ? 'Aggiornato al ' + ui.longDate(state.latest[gameId]) : 'Nessuna estrazione' })
            ]),
            el('span.num', { text: ui.integer(state.counts[gameId]),
              style: { fontWeight: '600', fontSize: '17px' } }),
            state.counts[gameId] > 0 ? el('button.btn.ghost', {
              text: 'Svuota',
              style: { color: 'var(--low)' },
              onclick: () => {
                if (!window.confirm('Eliminare tutte le estrazioni di ' + game.name
                  + '? L’operazione non è reversibile.')) return;
                Lotto.db.deleteGame(gameId).then(() => {
                  Lotto.app.toast('Archivio ' + game.name + ' svuotato.');
                  return reload();
                });
              }
            }) : null
          ]));
        });
        container.appendChild(ui.card('Archivio locale', '💾', [archive]));

        // --- Importazione
        const fileInput = el('input', {
          type: 'file',
          multiple: 'multiple',
          accept: '.csv,.txt,.tsv,.json,.xlsx,.xlsm,text/csv,application/json',
          style: { display: 'none' }
        });
        fileInput.addEventListener('change', () => handleFiles(fileInput.files));

        container.appendChild(ui.card('Importazione', '📥', [
          ui.select('Gioco del file', Object.keys(Lotto.GAMES).map((id) => ({
            id: id, name: Lotto.GAMES[id].name
          })), importGame, (value) => { importGame = value; }),
          fileInput,
          el('button.btn', {
            text: busy ? 'Importazione in corso…' : 'Scegli un file (CSV, JSON, Excel)',
            disabled: busy ? 'disabled' : null,
            onclick: () => fileInput.click()
          }),
          el('div', { style: { height: '8px' } }),
          el('button.btn.secondary', {
            text: 'Carica dati di esempio simulati',
            disabled: busy ? 'disabled' : null,
            onclick: () => {
              busy = true;
              Lotto.app.refresh();
              const records = Lotto.seed.generateSimulatedHistory(4);
              Lotto.db.insertDraws(records, 'dati di esempio').then((result) => {
                lastResult = result;
                busy = false;
                Lotto.app.toast(result.inserted + ' estrazioni simulate caricate.');
                return reload();
              }).catch((error) => {
                busy = false;
                Lotto.app.toast('Caricamento non riuscito: ' + error.message, true);
                Lotto.app.refresh();
              });
            }
          }),
          lastResult ? el('p.note', { text: lastResult.inserted + ' estrazioni importate · '
            + lastResult.duplicates + ' duplicati ignorati'
            + (lastResult.rejected ? ' · ' + lastResult.rejected + ' righe scartate' : '') }) : null,
          lastResult && lastResult.errors.length
            ? el('div', {}, lastResult.errors.map((error) =>
              el('p.note', { text: error, style: { color: 'var(--low)' } }))) : null,
          el('p.note', { text: 'Colonne riconosciute: data, ruota, numero1…numero6 (oppure n1…n6, o una singola colonna «numeri»), jolly, superstar. Date in formato gg/mm/aaaa, aaaa-mm-gg o ISO. I duplicati vengono ignorati, quindi è sicuro reimportare lo stesso file.' }),
          el('p.note', { text: 'I dati di esempio sono estrazioni SIMULATE, generate sul telefono: servono solo a provare l’interfaccia.',
            style: { fontWeight: '600' } })
        ]));

        // --- Sorgente remota
        container.appendChild(remoteSourceCard(reload));

        // --- Pesi dello scoring
        container.appendChild(weightsCard());

        // --- Aspetto
        container.appendChild(ui.card('Aspetto', '🎨', [
          ui.select('Tema', [
            { id: 'system', name: 'Automatico' },
            { id: 'light', name: 'Chiaro' },
            { id: 'dark', name: 'Scuro' }
          ], state.settings.theme, (value) => {
            state.settings.theme = value;
            Lotto.app.saveSettings();
            applyTheme(value);
          })
        ]));

        // --- Privacy
        container.appendChild(ui.card('Privacy', '🔒', [
          el('p.note', { text: 'L’app funziona interamente sul dispositivo. Le estrazioni sono conservate in un archivio locale del browser, separato dalle preferenze. Non è richiesta alcuna registrazione e nessun dato personale viene raccolto o inviato. Le uniche connessioni di rete sono quelle verso le sorgenti che configuri tu.' })
        ]));

        container.appendChild(ui.card('Informazioni', 'ℹ️', [
          el('div.rows', {}, [
            infoRow('Versione', '1.0'),
            infoRow('Estrazioni Lotto', ui.integer(state.counts.lotto)),
            infoRow('Estrazioni SuperEnalotto', ui.integer(state.counts.superenalotto))
          ])
        ]));

        container.appendChild(ui.disclaimer());
      }
    };
  };

  function infoRow(label, value) {
    return el('div.row', {}, [el('span.grow.note', { text: label }), el('span', { text: value })]);
  }

  function remoteSourceCard(reload) {
    let url = '';
    let game = Lotto.app.state.settings.defaultGame;
    const status = el('p.note');

    return ui.card('Sorgente remota', '🌐', [
      el('div.field', {}, [
        el('label', { text: 'Indirizzo (CSV, JSON o Excel)' }),
        (function () {
          const input = el('input', { type: 'url', placeholder: 'https://…', inputmode: 'url' });
          input.addEventListener('input', () => { url = input.value.trim(); });
          return input;
        })()
      ]),
      ui.select('Gioco', Object.keys(Lotto.GAMES).map((id) => ({ id: id, name: Lotto.GAMES[id].name })),
        game, (value) => { game = value; }),
      el('button.btn.secondary', {
        text: 'Scarica e importa',
        onclick: () => {
          if (!url) { status.textContent = 'Inserisci un indirizzo.'; return; }
          status.textContent = 'Scaricamento in corso…';
          Lotto.importer.importFromURL(url, game)
            .then((records) => Lotto.db.insertDraws(records, url))
            .then((result) => {
              status.textContent = result.inserted + ' estrazioni importate, '
                + result.duplicates + ' duplicati ignorati.';
              return reload();
            })
            .catch((error) => { status.textContent = 'Non riuscito: ' + error.message; });
        }
      }),
      status,
      el('p.note', { text: 'Inserisci l’indirizzo di un servizio che hai il diritto di utilizzare (API ufficiale, portale open data, un tuo export). Nessuna sorgente è preconfigurata. Il servizio deve consentire le richieste da altri siti (CORS), altrimenti il browser le bloccherà: in quel caso scarica il file e importalo dal telefono.' })
    ]);
  }

  function weightsCard() {
    const settings = Lotto.app.state.settings;
    const labels = [
      ['frequency', 'Frequenza'],
      ['recency', 'Recenza'],
      ['delay', 'Ritardo'],
      ['trend', 'Trend'],
      ['coOccurrence', 'Co-occorrenza'],
      ['stability', 'Stabilità']
    ];
    const body = el('div');

    labels.forEach((pair) => {
      const value = el('span.note', { text: Math.round((settings.weights[pair[0]] || 0) * 100) + '%' });
      const slider = el('input', {
        type: 'range', min: '0', max: '100', step: '5',
        value: String(Math.round((settings.weights[pair[0]] || 0) * 100))
      });
      slider.addEventListener('input', () => {
        settings.weights[pair[0]] = Number(slider.value) / 100;
        value.textContent = slider.value + '%';
      });
      slider.addEventListener('change', () => Lotto.app.saveSettings());
      body.appendChild(el('div', { style: { marginBottom: '10px' } }, [
        el('div', { style: { display: 'flex' } }, [
          el('span.grow.note', { text: pair[1] }), value
        ]),
        slider
      ]));
    });

    const presets = el('div.chips');
    [['balanced', 'Bilanciati'], ['frequencyFocused', 'Frequenza'],
      ['delayFocused', 'Ritardo'], ['trendFocused', 'Trend']].forEach((preset) => {
      presets.appendChild(el('button.chip', {
        text: preset[1],
        onclick: () => {
          settings.weights = Object.assign({}, Lotto.WEIGHT_PRESETS[preset[0]]);
          Lotto.app.saveSettings();
          Lotto.app.refresh();
        }
      }));
    });

    return ui.card('Pesi dello Statistical Number Score', '🎚️', [
      body,
      presets,
      el('p.note', { text: 'I pesi vengono normalizzati automaticamente, così l’indice resta sempre fra 0 e 100. L’indice descrive il comportamento passato di un numero e non è una probabilità di uscita.' })
    ]);
  }

  /** Forza il tema chiaro o scuro sovrascrivendo la preferenza di sistema. */
  function applyTheme(theme) {
    const root = document.documentElement;
    if (theme === 'light') root.style.colorScheme = 'light';
    else if (theme === 'dark') root.style.colorScheme = 'dark';
    else root.style.colorScheme = 'light dark';
    root.setAttribute('data-theme', theme);
  }

  views.applyTheme = applyTheme;
})(typeof self !== 'undefined' ? self : this);
