/* Schermate condivise: dashboard, dati/impostazioni e i controlli di filtro
   riusati da tutte le analisi. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const ui = Lotto.ui;
  const el = ui.el;
  const views = Lotto.views = Lotto.views || {};

  // ------------------------------------------------------------ Helper

  /** Selettori di gioco, ruota e periodo. `onChange` riceve il filtro aggiornato. */
  function filterControls(filter, onChange, options) {
    const settings = Object.assign({ game: true, wheel: true, period: true, allWheels: true }, options || {});
    const node = el('div');

    if (settings.game) {
      node.appendChild(ui.segmented(
        Object.keys(Lotto.GAMES).map((id) => ({ id: id, name: Lotto.GAMES[id].name })),
        filter.game,
        (game) => {
          filter.game = game;
          if (!Lotto.GAMES[game].usesWheels) filter.wheel = 'all';
          else if (filter.wheel === 'all' && !settings.allWheels) filter.wheel = 'Bari';
          onChange(filter);
        }));
    }

    const row = el('div.field-row');
    if (settings.wheel && Lotto.GAMES[filter.game].usesWheels) {
      const wheelOptions = (settings.allWheels ? [{ id: 'all', name: 'Tutte le ruote' }] : [])
        .concat(Lotto.WHEEL_IDS.map((id) => ({ id: id, name: id })));
      row.appendChild(ui.select('Ruota', wheelOptions, filter.wheel || 'all', (wheel) => {
        filter.wheel = wheel;
        onChange(filter);
      }));
    }
    if (settings.period) {
      row.appendChild(ui.select('Periodo', Lotto.PERIODS, filter.period, (period) => {
        filter.period = period;
        onChange(filter);
      }));
    }
    if (row.childNodes.length) node.appendChild(row);
    return node;
  }

  /**
   * Pannello che mostra un indicatore mentre il worker calcola e poi il
   * risultato. Centralizza anche la gestione degli errori.
   */
  function asyncPanel(container, label, task, renderResult) {
    const host = el('div');
    container.appendChild(host);
    const bar = ui.progress(label, 0);
    host.appendChild(bar);

    const onProgress = (value) => {
      const track = bar.querySelector('.track > span');
      if (track) track.style.width = (value * 100) + '%';
      const percent = bar.querySelector('div:last-child');
      if (percent) percent.textContent = Math.round(value * 100) + '%';
    };

    task(onProgress).then((result) => {
      ui.clear(host);
      renderResult(host, result);
    }).catch((error) => {
      ui.clear(host);
      host.appendChild(ui.empty('⚠️', 'Calcolo non riuscito', error.message || String(error)));
    });
    return host;
  }

  function requireData(container, gameId) {
    if (Lotto.app.state.counts[gameId] > 0) return false;
    container.appendChild(ui.empty('📥', 'Nessuna estrazione',
      'Importa lo storico di ' + Lotto.GAMES[gameId].name + ' dalla scheda Dati per iniziare.',
      'Vai ai dati', () => Lotto.app.push(views.data())));
    container.appendChild(ui.disclaimer());
    return true;
  }

  views.filterControls = filterControls;
  views.asyncPanel = asyncPanel;
  views.requireData = requireData;

  // --------------------------------------------------------- Dashboard

  views.dashboard = function () {
    return {
      title: 'Lotto AI Analyzer',
      render: function (container) {
        const state = Lotto.app.state;

        container.appendChild(ui.card('Archivio locale', '💾', [
          ui.metrics([
            ui.metric('Lotto', ui.integer(state.counts.lotto),
              state.latest.lotto ? 'Al ' + ui.shortDate(state.latest.lotto) : 'Nessun dato'),
            ui.metric('SuperEnalotto', ui.integer(state.counts.superenalotto),
              state.latest.superenalotto ? 'Al ' + ui.shortDate(state.latest.superenalotto) : 'Nessun dato')
          ]),
          Lotto.app.hasData() ? null : el('button.btn.secondary', {
            text: 'Importa lo storico per iniziare',
            onclick: () => Lotto.app.push(views.data())
          })
        ]));

        const game = state.settings.defaultGame;
        container.appendChild(ui.segmented(
          Object.keys(Lotto.GAMES).map((id) => ({ id: id, name: Lotto.GAMES[id].symbol + ' ' + Lotto.GAMES[id].name })),
          game,
          (selected) => {
            state.settings.defaultGame = selected;
            if (!Lotto.GAMES[selected].usesWheels) state.settings.defaultWheel = 'Bari';
            Lotto.app.saveSettings();
            Lotto.app.refresh();
          }));

        const tiles = [
          ['📊', 'Analisi', 'Frequenze, ritardi, distribuzioni', () => views.analysis(game)],
          ['🔥', 'Numeri hot', 'Frequenza recente in crescita', () => views.hotCold(game, 'hot')],
          ['❄️', 'Numeri cold', 'Frequenza recente in calo', () => views.hotCold(game, 'cold')],
          ['⏳', 'Ritardatari', 'Estrazioni dall’ultima uscita', () => views.delays(game)],
          ['🔗', 'Ambi', 'Top coppie statisticamente interessanti', () => views.pairs(game)],
          ['🔺', 'Terni', 'Top combinazioni di tre numeri', () => views.triples(game)],
          ['🎯', game === 'lotto' ? 'Cinquina AI' : 'Sestina AI', 'Quattro modalità di generazione',
            () => views.quintuples(game)]
        ];
        if (game === 'lotto') {
          tiles.push(['🎡', 'Multi-ruota', 'Segnali comuni a più ruote', () => views.multiWheel()]);
        }
        tiles.push(
          ['🧪', 'Backtest', 'Simulazione walk-forward', () => views.backtest()],
          ['🤖', 'AI Analyst', 'Modelli sperimentali e validazione', () => views.machineLearning()],
          ['🔍', 'Trova pattern', 'Ricorrenze e anomalie', () => views.patterns()],
          ['🎲', 'Monte Carlo', 'Confronto con la casualità', () => views.monteCarlo()],
          ['⚖️', 'Confronto', 'Fino a 10 combinazioni', () => views.compare()],
          ['📥', 'Dati', 'Import, sorgenti e archivio', () => views.data()]
        );

        const grid = el('div.grid');
        tiles.forEach((tile) => {
          grid.appendChild(el('button.tile', { onclick: () => Lotto.app.push(tile[3]()) }, [
            el('span.emoji', { text: tile[0] }),
            el('span.title', { text: tile[1] }),
            el('span.desc', { text: tile[2] })
          ]));
        });
        container.appendChild(grid);
        container.appendChild(el('div', { style: { height: '14px' } }));
        container.appendChild(ui.disclaimer());
      }
    };
  };

  // ------------------------------------------------------- Indici tab

  views.analysisHome = function () {
    return {
      title: 'Analisi',
      render: function (container) {
        const game = Lotto.app.state.settings.defaultGame;
        container.appendChild(ui.segmented(
          Object.keys(Lotto.GAMES).map((id) => ({ id: id, name: Lotto.GAMES[id].name })),
          game,
          (selected) => {
            Lotto.app.state.settings.defaultGame = selected;
            Lotto.app.saveSettings();
            Lotto.app.refresh();
          }));

        const groups = [
          ['Statistiche', [
            ['📊', 'Analisi annuale e multi-anno', () => views.analysis(game)],
            ['⏳', 'Numeri ritardatari', () => views.delays(game)],
            ['🌡️', 'Caldi, freddi e ritardatari', () => views.hotCold(game, 'hot')]
          ]],
          ['Combinazioni', [
            ['🔗', 'Ambi', () => views.pairs(game)],
            ['🔺', 'Terni', () => views.triples(game)],
            ['🎯', game === 'lotto' ? 'Cinquina AI' : 'Sestina AI', () => views.quintuples(game)]
          ].concat(game === 'lotto' ? [['🎡', 'Analisi multi-ruota', () => views.multiWheel()]] : [])]
        ];

        groups.forEach((group) => {
          const rows = el('div.rows');
          group[1].forEach((item) => {
            rows.appendChild(el('div.row.tappable', { onclick: () => Lotto.app.push(item[2]()) }, [
              el('span', { text: item[0] }),
              el('span.grow', { text: item[1] }),
              el('span', { text: '›', style: { color: 'var(--text-secondary)' } })
            ]));
          });
          container.appendChild(ui.card(group[0], null, [rows]));
        });
        container.appendChild(ui.disclaimer());
      }
    };
  };

  views.generateHome = function () {
    return views.smartGenerator();
  };

  views.labHome = function () {
    return {
      title: 'Verifica',
      render: function (container) {
        const groups = [
          ['Verifica delle strategie', [
            ['🧪', 'Backtest e validazione', () => views.backtest()],
            ['🎲', 'Simulazione Monte Carlo', () => views.monteCarlo()]
          ]],
          ['Modelli e pattern', [
            ['🤖', 'AI Analyst', () => views.machineLearning()],
            ['🔍', 'Trova pattern', () => views.patterns()]
          ]],
          ['Combinazioni', [
            ['⚖️', 'Confronto combinazioni', () => views.compare()]
          ]]
        ];
        groups.forEach((group) => {
          const rows = el('div.rows');
          group[1].forEach((item) => {
            rows.appendChild(el('div.row.tappable', { onclick: () => Lotto.app.push(item[2]()) }, [
              el('span', { text: item[0] }),
              el('span.grow', { text: item[1] }),
              el('span', { text: '›', style: { color: 'var(--text-secondary)' } })
            ]));
          });
          container.appendChild(ui.card(group[0], null, [rows]));
        });
        container.appendChild(ui.disclaimer());
      }
    };
  };

  views.forTab = function (tabId) {
    switch (tabId) {
      case 'analysis': return views.analysisHome();
      case 'generate': return views.generateHome();
      case 'lab': return views.labHome();
      case 'settings': return views.data();
      default: return views.dashboard();
    }
  };
})(typeof self !== 'undefined' ? self : this);
