/* Schermate di generazione e verifica: ambi, terni, cinquine, generatore
   guidato, multi-ruota, backtest, confronto e pagina risultato. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const ui = Lotto.ui;
  const el = ui.el;
  const views = Lotto.views = Lotto.views || {};
  const charts = Lotto.charts;

  function scoreMapFor(summary, numbers) {
    const map = {};
    if (!summary) return map;
    numbers.forEach((number) => {
      const entry = summary.numbers[number - 1];
      if (entry) map[number] = entry.score;
    });
    return map;
  }

  // ------------------------------------------------------------- Ambi

  views.pairs = function (gameId) {
    const filter = Lotto.app.defaultFilter(gameId);
    filter.wheel = filter.wheel === 'all' && Lotto.GAMES[filter.game].usesWheels ? 'Bari' : filter.wheel;
    let started = false;
    const expanded = {};

    return {
      title: 'Ambi',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;

        container.appendChild(ui.card(null, null, [
          views.filterControls(filter, () => { started = false; Lotto.app.refresh(); },
            { game: false, allWheels: false }),
          el('button.btn', { text: 'Genera ambi', onclick: () => { started = true; Lotto.app.refresh(); } })
        ]));

        if (!started) {
          container.appendChild(ui.empty('🔗', 'Nessun ambo calcolato',
            'Tocca «Genera ambi» per analizzare tutte le 4.005 coppie possibili.'));
          container.appendChild(ui.disclaimer());
          return;
        }

        views.asyncPanel(container, 'Analisi delle 4.005 coppie possibili…',
          (onProgress) => Lotto.app.compute('pairs',
            { filter: filter, limit: 10, weights: Lotto.app.state.settings.weights }, onProgress),
          (host, result) => {
            host.appendChild(el('p.note', { text: 'TOP ' + result.pairs.length
              + ' AMBI STATISTICAMENTE INTERESSANTI', style: { fontWeight: '700', letterSpacing: '0.03em' } }));

            result.pairs.forEach((pair, index) => {
              const key = pair.first + '-' + pair.second;
              const body = [
                el('div', { style: { display: 'flex', alignItems: 'center', gap: '10px' } }, [
                  el('span', { text: (index + 1) + '.',
                    style: { fontWeight: '600', color: 'var(--text-secondary)', minWidth: '20px' } }),
                  ui.combinationRow(pair.numbers, scoreMapFor(result.summary, pair.numbers)),
                  el('span.grow'),
                  ui.scoreBadge(pair.score)
                ]),
                ui.metrics([
                  ui.metric('Uscite', String(pair.jointCount), 'attese ' + ui.decimal(pair.expectedCount)),
                  ui.metric('Rapporto', ui.decimal(pair.lift, 2) + '×', null,
                    pair.lift > 1.15 ? 'var(--high)' : null),
                  ui.metric('Ritardo', String(pair.delay)),
                  ui.metric('Recenti', String(pair.recentCount))
                ]),
                el('button.btn.ghost', {
                  text: expanded[key] ? 'Nascondi' : 'Perché?',
                  onclick: () => { expanded[key] = !expanded[key]; Lotto.app.refresh(); }
                })
              ];
              if (expanded[key]) body.push(ui.reasonsList(pair.reasons));
              host.appendChild(ui.card(null, null, body));
            });
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  // ------------------------------------------------------------ Terni

  views.triples = function (gameId) {
    const filter = Lotto.app.defaultFilter(gameId);
    filter.wheel = filter.wheel === 'all' && Lotto.GAMES[filter.game].usesWheels ? 'Bari' : filter.wheel;
    let started = false;
    let fullSearch = false;
    const expanded = {};

    return {
      title: 'Terni',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;

        container.appendChild(ui.card(null, null, [
          views.filterControls(filter, () => { started = false; Lotto.app.refresh(); },
            { game: false, allWheels: false }),
          ui.segmented([
            { id: 'fast', name: 'Migliori 45 numeri' },
            { id: 'full', name: 'Tutte le 117.480 terne' }
          ], fullSearch ? 'full' : 'fast', (value) => {
            fullSearch = value === 'full'; started = false; Lotto.app.refresh();
          }),
          el('p.note', { text: fullSearch
            ? 'Vengono valutate tutte le terne possibili: il calcolo richiede qualche secondo.'
            : 'Vengono valutate le terne composte dai 45 numeri con indice statistico più alto.' }),
          el('button.btn', { text: 'Genera terni', onclick: () => { started = true; Lotto.app.refresh(); } })
        ]));

        if (!started) {
          container.appendChild(ui.empty('🔺', 'Nessun terno calcolato',
            'Tocca «Genera terni» per esplorare le combinazioni di tre numeri.'));
          container.appendChild(ui.disclaimer());
          return;
        }

        views.asyncPanel(container, 'Analisi delle combinazioni di tre numeri…',
          (onProgress) => Lotto.app.compute('triples',
            { filter: filter, limit: 10, poolSize: fullSearch ? 90 : 45,
              weights: Lotto.app.state.settings.weights }, onProgress),
          (host, result) => {
            host.appendChild(el('p.note', { text: 'TOP ' + result.triples.length + ' TERNI',
              style: { fontWeight: '700', letterSpacing: '0.03em' } }));

            result.triples.forEach((triple, index) => {
              const key = triple.numbers.join('-');
              const body = [
                el('div', { style: { display: 'flex', alignItems: 'center', gap: '10px' } }, [
                  el('span', { text: (index + 1) + '.',
                    style: { fontWeight: '600', color: 'var(--text-secondary)', minWidth: '20px' } }),
                  ui.combinationRow(triple.numbers, scoreMapFor(result.summary, triple.numbers)),
                  el('span.grow'),
                  ui.scoreBadge(triple.score)
                ]),
                ui.metrics([
                  ui.metric('Terna uscita', String(triple.jointCount),
                    'attese ' + ui.decimal(triple.expectedCount, 2)),
                  ui.metric('Coppie interne', ui.decimal(triple.averagePairCount)),
                  ui.metric('Somma', String(triple.sum)),
                  ui.metric('Pari/disp.', triple.evenCount + '/' + (3 - triple.evenCount))
                ]),
                el('button.btn.ghost', {
                  text: expanded[key] ? 'Nascondi' : 'Perché?',
                  onclick: () => { expanded[key] = !expanded[key]; Lotto.app.refresh(); }
                })
              ];
              if (expanded[key]) body.push(ui.reasonsList(triple.reasons));
              host.appendChild(ui.card(null, null, body));
            });
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  // --------------------------------------------------------- Cinquine

  views.quintuples = function (gameId) {
    const filter = Lotto.app.defaultFilter(gameId);
    filter.wheel = filter.wheel === 'all' && Lotto.GAMES[filter.game].usesWheels ? 'Bari' : filter.wheel;
    let mode = 'balanced';
    let count = 5;
    let started = false;

    return {
      title: Lotto.GAMES[filter.game].drawnCount === 5 ? 'Cinquina AI' : 'Sestina AI',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;

        const modeButtons = el('div');
        Lotto.QUINTUPLE_MODES.forEach((item) => {
          modeButtons.appendChild(el('button.row.tappable', {
            style: { width: '100%', background: 'none', border: 'none', textAlign: 'left' },
            onclick: () => { mode = item.id; started = false; Lotto.app.refresh(); }
          }, [
            el('span', { text: mode === item.id ? '◉' : '○',
              style: { color: mode === item.id ? 'var(--accent)' : 'var(--text-secondary)' } }),
            el('span.grow', {}, [
              el('div', { text: item.name, style: { fontWeight: '500' } }),
              el('div.note', { text: item.subtitle })
            ])
          ]));
        });

        container.appendChild(ui.card('Modalità di generazione', '🎚️', [
          modeButtons,
          views.filterControls(filter, () => { started = false; Lotto.app.refresh(); },
            { game: false, allWheels: false }),
          ui.select('Combinazioni da generare',
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((n) => ({ id: String(n), name: String(n) })),
            String(count), (value) => { count = Number(value); }),
          el('button.btn', { text: 'Genera', onclick: () => { started = true; Lotto.app.refresh(); } })
        ]));

        if (!started) {
          container.appendChild(ui.empty('🎯', 'Nessuna combinazione generata',
            'Scegli una modalità e genera le combinazioni.'));
          container.appendChild(ui.disclaimer());
          return;
        }

        views.asyncPanel(container, 'Generazione delle combinazioni…',
          (onProgress) => Lotto.app.compute('combinations',
            { filter: filter, mode: mode, count: count, seed: Date.now() % 1000000,
              weights: Lotto.weightsForStrategy(mode) }, onProgress),
          (host, result) => {
            if (!result.combinations.length) {
              host.appendChild(ui.empty('📭', 'Nessuna combinazione',
                'Il periodo selezionato non contiene abbastanza estrazioni.'));
              return;
            }
            result.combinations.forEach((combination, index) => {
              host.appendChild(combinationCard(combination, index, result.summary, filter, mode));
            });
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  function combinationCard(combination, index, summary, filter, strategyId) {
    return ui.card(null, null, [
      el('div', { style: { display: 'flex', alignItems: 'center' } }, [
        el('span.grow.note', { text: 'Combinazione ' + (index + 1), style: { fontWeight: '600' } }),
        ui.scoreBadge(combination.score)
      ]),
      ui.combinationRow(combination.numbers, scoreMapFor(summary, combination.numbers)),
      ui.metrics([
        ui.metric('Pari/disp.', evenOdd(combination.numbers)),
        ui.metric('1–45 / 46–90', lowHigh(combination.numbers)),
        ui.metric('Somma', String(sum(combination.numbers)))
      ]),
      combination.reasons && combination.reasons.length
        ? el('p.note', { text: combination.reasons[0] }) : null,
      el('div.btn-row', {}, [
        el('button.btn.secondary', {
          text: 'Motivazioni',
          onclick: () => Lotto.app.push(views.result(combination, summary, filter, strategyId))
        }),
        el('button.btn.secondary', {
          text: '🔖 Salva',
          onclick: () => saveCombination(combination, filter, strategyId)
        })
      ])
    ]);
  }

  function sum(numbers) { let total = 0; numbers.forEach((n) => { total += n; }); return total; }
  function evenOdd(numbers) {
    const even = numbers.filter((n) => n % 2 === 0).length;
    return even + '/' + (numbers.length - even);
  }
  function lowHigh(numbers) {
    const low = numbers.filter((n) => n <= 45).length;
    return low + '/' + (numbers.length - low);
  }

  function saveCombination(combination, filter, strategyId) {
    Lotto.db.saveCombination({
      createdAt: Date.now(),
      numbers: combination.numbers,
      score: combination.score,
      components: combination.components,
      game: filter.game,
      wheel: filter.wheel,
      period: filter.period,
      strategy: strategyId,
      reasons: combination.reasons || []
    }).then(() => Lotto.app.toast('Combinazione salvata.'))
      .catch((error) => Lotto.app.toast('Salvataggio non riuscito: ' + error.message, true));
  }

  // -------------------------------------------------- Pagina risultato

  views.result = function (combination, summary, filter, strategyId) {
    return {
      title: 'Combinazione',
      render: function (container) {
        container.appendChild(ui.card(null, null, [
          el('p.note', { text: '🎯 COMBINAZIONE', style: { fontWeight: '700', letterSpacing: '0.03em' } }),
          ui.combinationRow(combination.numbers, scoreMapFor(summary, combination.numbers), 'lg'),
          el('div', { style: { display: 'flex', alignItems: 'baseline', marginTop: '8px' } }, [
            el('span.grow.note', { text: 'Statistical Score' }),
            el('span', { text: Math.round(combination.score) + '/100',
              style: { fontSize: '22px', fontWeight: '700', color: ui.scoreColor(combination.score) } })
          ]),
          el('p.note', { text: Lotto.scoreBand(combination.score).emoji + ' '
            + Lotto.scoreBand(combination.score).label }),
          el('p.note', { text: summary ? summary.description : '' })
        ]));

        const components = combination.components || {};
        container.appendChild(ui.card('Analisi', '📈', [
          qualitativeRow('🔥 Frequenza', components.frequency),
          qualitativeRow('⏳ Ritardo', components.delay),
          qualitativeRow('📈 Trend', components.trend),
          qualitativeRow('🔗 Co-occorrenza', components.coOccurrence),
          qualitativeRow('⚖️ Equilibrio', components.balance)
        ]));

        const decades = {};
        combination.numbers.forEach((number) => {
          const decade = Math.min(Math.floor((number - 1) / 10), 8);
          decades[decade] = (decades[decade] || 0) + 1;
        });
        container.appendChild(ui.card('Distribuzione', '🔢', [
          ui.metrics([
            ui.metric('Pari', String(combination.numbers.filter((n) => n % 2 === 0).length)),
            ui.metric('Dispari', String(combination.numbers.filter((n) => n % 2 !== 0).length)),
            ui.metric('1–45', String(combination.numbers.filter((n) => n <= 45).length)),
            ui.metric('46–90', String(combination.numbers.filter((n) => n > 45).length)),
            ui.metric('Somma', String(sum(combination.numbers)))
          ]),
          charts.barChart([0, 1, 2, 3, 4, 5, 6, 7, 8].map((decade) => ({
            label: (decade * 10 + 1) + '–' + (decade * 10 + 10),
            value: decades[decade] || 0
          })), { height: 120, minWidth: 340 })
        ]));

        const bars = el('div');
        Lotto.labelledComponents(components).forEach((item) => {
          bars.appendChild(ui.barRow(item.label, item.value));
        });
        container.appendChild(ui.card('Scomposizione dell’indice', '🎚️', [bars]));

        (combination.explanation || []).forEach((section) => {
          container.appendChild(ui.card(section.title, section.icon, [
            el('p.pre-wrap', { text: section.body })
          ]));
        });

        container.appendChild(el('button.btn.secondary', {
          text: '🔖 Salva combinazione',
          onclick: () => saveCombination(combination, filter, strategyId)
        }));
        container.appendChild(el('div', { style: { height: '12px' } }));
        container.appendChild(ui.disclaimer(Lotto.DISCLAIMER.score, 'ℹ️'));
      }
    };
  };

  function qualitativeRow(label, value) {
    const level = value >= 70 ? 'alta' : (value >= 40 ? 'media' : 'bassa');
    return el('div.row', {}, [
      el('span.grow', { text: label }),
      el('span', { text: level, style: { color: ui.scoreColor(value || 0), fontWeight: '500' } }),
      el('span.note', { text: '(' + Math.round(value || 0) + ')' })
    ]);
  }

  // ------------------------------------------------- Generatore guidato

  views.smartGenerator = function () {
    const filter = Lotto.app.defaultFilter();
    let strategy = 'balanced';
    let count = 5;
    let showResults = false;

    return {
      title: '🔮 Genera combinazione',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;

        if (!showResults) {
          container.appendChild(ui.card('1. Gioco', '🎮', [
            ui.segmented(Object.keys(Lotto.GAMES).map((id) => ({
              id: id, name: Lotto.GAMES[id].symbol + ' ' + Lotto.GAMES[id].name
            })), filter.game, (game) => {
              filter.game = game;
              filter.wheel = Lotto.GAMES[game].usesWheels ? 'Bari' : 'all';
              Lotto.app.refresh();
            }),
            Lotto.GAMES[filter.game].usesWheels
              ? ui.select('Ruota', [{ id: 'all', name: 'Tutte le ruote' }]
                .concat(Lotto.WHEEL_IDS.map((id) => ({ id: id, name: id }))),
                filter.wheel, (wheel) => { filter.wheel = wheel; })
              : null
          ]));

          const strategyList = el('div');
          Lotto.STRATEGIES.filter((item) => item.id !== 'conservative' && item.id !== 'diversified')
            .forEach((item) => {
              strategyList.appendChild(el('button.row.tappable', {
                style: { width: '100%', background: 'none', border: 'none', textAlign: 'left' },
                onclick: () => { strategy = item.id; Lotto.app.refresh(); }
              }, [
                el('span', { text: strategy === item.id ? '◉' : '○',
                  style: { color: strategy === item.id ? 'var(--accent)' : 'var(--text-secondary)' } }),
                el('span.grow', {}, [
                  el('div', { text: item.name, style: { fontWeight: '500' } }),
                  el('div.note', { text: item.explanation })
                ])
              ]));
            });
          container.appendChild(ui.card('2. Strategia', '🎯', [strategyList]));

          container.appendChild(ui.card('3. Periodo', '📅', [
            ui.select('Periodo', Lotto.PERIODS, filter.period, (period) => { filter.period = period; }),
            ui.select('Combinazioni da generare',
              [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((n) => ({ id: String(n), name: String(n) })),
              String(count), (value) => { count = Number(value); })
          ]));

          container.appendChild(el('button.btn', {
            text: '🔮 Genera combinazione',
            onclick: () => { showResults = true; Lotto.app.refresh(); }
          }));
          container.appendChild(el('div', { style: { height: '12px' } }));
          container.appendChild(ui.disclaimer());
          return;
        }

        container.appendChild(el('button.btn.secondary', {
          text: '‹ Modifica impostazioni',
          onclick: () => { showResults = false; Lotto.app.refresh(); }
        }));
        container.appendChild(el('div', { style: { height: '12px' } }));

        views.asyncPanel(container, 'Generazione delle combinazioni…',
          (onProgress) => Lotto.app.compute('combinations',
            { filter: filter, strategy: strategy, mode: 'balanced', count: count,
              seed: Date.now() % 1000000, weights: Lotto.weightsForStrategy(strategy) }, onProgress),
          (host, result) => {
            const strategyInfo = Lotto.STRATEGIES.find((item) => item.id === strategy);
            host.appendChild(ui.card('Impostazioni usate', 'ℹ️', [
              el('div.rows', {}, [
                infoRow('Gioco', Lotto.GAMES[filter.game].name),
                Lotto.GAMES[filter.game].usesWheels
                  ? infoRow('Ruota', filter.wheel === 'all' ? 'Tutte le ruote' : filter.wheel) : null,
                infoRow('Strategia', strategyInfo.name),
                infoRow('Periodo', Lotto.periodById(filter.period).name),
                infoRow('Estrazioni analizzate', ui.integer(result.summary.drawCount))
              ].filter(Boolean))
            ]));
            result.combinations.forEach((combination, index) => {
              host.appendChild(combinationCard(combination, index, result.summary, filter, strategy));
            });
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  function infoRow(label, value) {
    return el('div.row', {}, [el('span.grow.note', { text: label }), el('span', { text: value })]);
  }

  // ------------------------------------------------------ Multi-ruota

  views.multiWheel = function () {
    const filter = { game: 'lotto', wheel: 'all', period: Lotto.app.state.settings.defaultPeriod };
    let section = 'numbers';
    let started = false;

    return {
      title: 'Multi-ruota',
      render: function (container) {
        if (views.requireData(container, 'lotto')) return;

        container.appendChild(ui.card(null, null, [
          ui.select('Periodo', Lotto.PERIODS, filter.period, (period) => {
            filter.period = period; started = false; Lotto.app.refresh();
          }),
          el('button.btn', { text: 'Analizza tutte le ruote',
            onclick: () => { started = true; Lotto.app.refresh(); } })
        ]));

        if (!started) {
          container.appendChild(ui.empty('🎡', 'Analisi non ancora eseguita',
            'Il calcolo esamina tutte e undici le ruote e richiede qualche secondo.'));
          container.appendChild(ui.disclaimer());
          return;
        }

        views.asyncPanel(container, 'Analisi simultanea di tutte le ruote…',
          (onProgress) => Lotto.app.compute('multiWheel',
            { filter: filter, weights: Lotto.app.state.settings.weights, seed: 42 }, onProgress),
          (host, result) => {
            host.appendChild(ui.segmented([
              { id: 'numbers', name: 'Numeri' },
              { id: 'pairs', name: 'Ambi' },
              { id: 'triples', name: 'Terni' },
              { id: 'combination', name: 'Cinquina' }
            ], section, (selected) => { section = selected; Lotto.app.refresh(); }));

            if (section === 'numbers') {
              const rows = el('div.rows');
              rows.appendChild(el('div.row.header', {}, [
                el('span', { text: 'N.', style: { width: '28px' } }),
                el('span.grow', { text: 'Ruote' }),
                el('span.num', { text: 'Usc.', style: { width: '46px' } }),
                el('span.num', { text: 'Indice', style: { width: '46px' } })
              ]));
              result.numbers.forEach((item) => {
                rows.appendChild(el('div.row', {}, [
                  el('span', { text: ui.pad(item.number), style: { width: '28px', fontWeight: '600' } }),
                  el('span.grow.note', { text: item.wheelCodes }),
                  el('span.num', { text: String(item.totalOccurrences), style: { width: '46px' } }),
                  el('span.num', { text: String(Math.round(item.score)),
                    style: { width: '46px', color: ui.scoreColor(item.score), fontWeight: '600' } })
                ]));
              });
              host.appendChild(ui.card('Numeri con segnali su più ruote', '🎡', [rows],
                'Numero · ruote · frequenza complessiva · indice'));
            } else if (section === 'combination') {
              if (!result.combination) {
                host.appendChild(ui.empty('📭', 'Nessuna combinazione multi-ruota',
                  'Servono numeri con segnali su più ruote nel periodo selezionato.'));
              } else {
                const combination = result.combination.combination;
                host.appendChild(ui.card('CINQUINA MULTI-RUOTA', '🎯', [
                  ui.combinationRow(combination.numbers, null, 'lg'),
                  el('div', { style: { display: 'flex', alignItems: 'center' } }, [
                    el('span.grow.note', { text: 'Indice statistico' }),
                    ui.scoreBadge(combination.score)
                  ]),
                  result.combination.wheels.length
                    ? el('p.note', { text: 'Ruote con i segnali più forti: '
                      + result.combination.wheels.join(', ') + '.' }) : null,
                  ui.reasonsList(combination.reasons)
                ]));
              }
            } else {
              const items = section === 'pairs' ? result.pairs : result.triples;
              host.appendChild(el('p.note', {
                text: section === 'pairs' ? 'TOP AMBI MULTI-RUOTA' : 'TOP TERNI MULTI-RUOTA',
                style: { fontWeight: '700', letterSpacing: '0.03em' }
              }));
              if (!items.length) {
                host.appendChild(el('p.note', { text: 'Nessun risultato per il periodo selezionato.' }));
              }
              items.forEach((item, index) => {
                host.appendChild(ui.card(null, null, [
                  el('div', { style: { display: 'flex', alignItems: 'center', gap: '10px' } }, [
                    el('span', { text: (index + 1) + '.',
                      style: { fontWeight: '600', color: 'var(--text-secondary)', minWidth: '20px' } }),
                    ui.combinationRow(item.numbers, null),
                    el('span.grow'),
                    ui.scoreBadge(item.score)
                  ]),
                  ui.metrics([
                    ui.metric('Ruote', String(item.wheelCount)),
                    ui.metric('Uscite', String(item.totalJointCount)),
                    ui.metric('Rit. medio', ui.decimal(item.averageDelay))
                  ]),
                  ui.reasonsList(item.reasons)
                ]));
              });
            }
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  // --------------------------------------------------------- Backtest

  views.backtest = function () {
    const now = Date.now();
    const configuration = {
      game: Lotto.app.state.settings.defaultGame,
      wheel: Lotto.app.state.settings.defaultWheel,
      lookback: 'fiveYears',
      startDate: now - 365 * 86400000,
      endDate: now,
      kind: 'pairs',
      mode: 'balanced',
      playsPerDraw: 3,
      stakePerPlay: 1,
      minimumHistory: 60,
      candidatePoolSize: 40,
      seed: 7,
      weights: Lotto.app.state.settings.weights
    };
    let mode = null;

    return {
      title: 'Backtest',
      render: function (container) {
        if (views.requireData(container, configuration.game)) return;

        container.appendChild(ui.card('Configurazione', '🎚️', [
          ui.segmented(Object.keys(Lotto.GAMES).map((id) => ({ id: id, name: Lotto.GAMES[id].name })),
            configuration.game, (game) => {
              configuration.game = game;
              configuration.wheel = Lotto.GAMES[game].usesWheels ? 'Bari' : 'all';
              mode = null; Lotto.app.refresh();
            }),
          Lotto.GAMES[configuration.game].usesWheels
            ? ui.select('Ruota', Lotto.WHEEL_IDS.map((id) => ({ id: id, name: id })),
              configuration.wheel, (wheel) => { configuration.wheel = wheel; }) : null,
          ui.select('Strategia', Lotto.STRATEGY_KINDS.map((kind) => ({ id: kind.id, name: kind.name })),
            configuration.kind, (kind) => { configuration.kind = kind; mode = null; Lotto.app.refresh(); }),
          configuration.kind === 'quintuples'
            ? ui.select('Modalità', Lotto.QUINTUPLE_MODES, configuration.mode,
              (value) => { configuration.mode = value; }) : null,
          ui.select('Finestra storica', Lotto.PERIODS, configuration.lookback,
            (value) => { configuration.lookback = value; }),
          dateField('Dal', configuration.startDate, (value) => { configuration.startDate = value; }),
          dateField('Al', configuration.endDate, (value) => { configuration.endDate = value; }),
          ui.select('Giocate per estrazione',
            [1, 2, 3, 4, 5, 6, 8, 10].map((n) => ({ id: String(n), name: String(n) })),
            String(configuration.playsPerDraw), (value) => { configuration.playsPerDraw = Number(value); }),
          el('div.btn-row', {}, [
            el('button.btn', { text: 'Esegui backtest', onclick: () => { mode = 'backtest'; Lotto.app.refresh(); } }),
            el('button.btn.secondary', { text: 'Valida', onclick: () => { mode = 'validate'; Lotto.app.refresh(); } })
          ])
        ]));

        container.appendChild(ui.card('Protezione dal data leakage', '🔒', [
          el('p.note', { text: Lotto.DISCLAIMER.backtest }),
          el('p.note', { text: 'A ogni passo il motore ricostruisce le statistiche applicando un limite temporale stretto: nessuna estrazione con data uguale o successiva a quella simulata entra nel calcolo di frequenze, ritardi o co-occorrenze.' })
        ]));

        if (!mode) { container.appendChild(ui.disclaimer()); return; }

        const payload = { configuration: Object.assign({}, configuration,
          { weights: Lotto.app.state.settings.weights }) };

        views.asyncPanel(container, mode === 'validate'
          ? 'Validazione completa in corso…' : 'Simulazione walk-forward in corso…',
          (onProgress) => Lotto.app.compute(mode === 'validate' ? 'validate' : 'backtest', payload, onProgress),
          (host, response) => {
            const report = response.report || null;
            const result = report ? report.backtest : response.result;
            if (!result || !result.drawsEvaluated) {
              host.appendChild(ui.empty('📭', 'Backtest non eseguibile',
                'Nel periodo scelto non ci sono abbastanza estrazioni precedenti per applicare la strategia (servono almeno '
                + configuration.minimumHistory + ' estrazioni di storico).'));
              return;
            }
            renderBacktest(host, result);
            if (report) renderValidation(host, report);
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  function dateField(label, timestamp, onChange) {
    const input = el('input', { type: 'date', value: ui.isoDate(timestamp) });
    input.addEventListener('change', () => {
      const parsed = Date.parse(input.value + 'T12:00:00Z');
      if (!isNaN(parsed)) onChange(parsed);
    });
    return el('div.field', {}, [el('label', { text: label }), input]);
  }

  function renderBacktest(host, result) {
    host.appendChild(ui.card('Verdetto', '✅', [
      el('p', { text: result.verdict, style: { fontSize: '14px' } }),
      el('p.note', { text: result.significance.interpretation })
    ]));

    const sorteName = { 2: 'Ambi centrati', 3: 'Terni centrati', 4: 'Quaterne centrate',
      5: 'Cinquine centrate', 6: 'Sestine centrate' };
    const hitRows = [2, 3, 4, 5, 6]
      .filter((matched) => (result.strategy.hitDistribution[matched] || 0) > 0
        || (result.baseline.hitDistribution[matched] || 0) > 0)
      .map((matched) => infoRow(sorteName[matched],
        (result.strategy.hitDistribution[matched] || 0) + ' (baseline '
        + (result.baseline.hitDistribution[matched] || 0) + ')'));

    host.appendChild(ui.card('Risultati teorici', '💶', [
      ui.metrics([
        ui.metric('Estrazioni', ui.integer(result.drawsEvaluated)),
        ui.metric('Giocate', ui.integer(result.strategy.totalPlays)),
        ui.metric('Centrate', ui.integer(result.strategy.winningPlays),
          ui.percent(result.strategy.hitRate * 100, 2))
      ]),
      el('div.rows', {}, [
        infoRow('Costo teorico', ui.currency(result.strategy.totalCost)),
        infoRow('Vincite teoriche', ui.currency(result.strategy.totalWinnings)),
        infoRow('Saldo teorico', ui.currency(result.strategy.net)),
        infoRow('ROI teorico', ui.percent(result.strategy.roi)),
        infoRow('Baseline: centrate', result.baseline.winningPlays + ' ('
          + ui.percent(result.baseline.hitRate * 100, 2) + ')'),
        infoRow('Baseline: ROI', ui.percent(result.baseline.roi))
      ].concat(hitRows))
    ]));

    let cumulative = 0;
    const curve = result.steps.map((step) => {
      cumulative += step.net;
      return { value: cumulative };
    });
    if (curve.length) {
      host.appendChild(ui.card('Saldo teorico cumulato', '📈', [
        charts.lineChart(curve),
        el('p.note', { text: 'Il saldo include il costo di ogni giocata simulata e le vincite calcolate con i moltiplicatori teorici.' })
      ]));
    }

    const keys = Array.from(new Set(Object.keys(result.strategy.hitDistribution)
      .concat(Object.keys(result.baseline.hitDistribution)))).map(Number).sort((a, b) => a - b);
    host.appendChild(ui.card('Numeri indovinati: strategia contro baseline', '📊', [
      charts.groupedBars(keys.map((key) => ({
        label: String(key),
        a: result.strategy.hitDistribution[key] || 0,
        b: result.baseline.hitDistribution[key] || 0
      })), { labels: ['Strategia', 'Baseline'] })
    ]));

    const stepsBody = el('div');
    result.steps.slice(-40).reverse().forEach((step) => {
      stepsBody.appendChild(el('div', { style: { padding: '7px 0', borderTop: '1px solid var(--separator)' } }, [
        el('div', { style: { display: 'flex' } }, [
          el('span.grow', { text: ui.shortDate(step.date), style: { fontWeight: '600', fontSize: '13px' } }),
          el('span.note', { text: 'miglior risultato: ' + step.bestMatch,
            style: { color: step.bestMatch >= 2 ? 'var(--high)' : null } })
        ]),
        el('p.note', { text: 'Estratti: ' + step.drawnNumbers.map(ui.pad).join(' ') }),
        el('p.note', { text: 'Giocate: ' + step.plays.map((play) => play.map(ui.pad).join('-')).join('  ') })
      ]));
    });
    host.appendChild(ui.card('Dettaglio estrazioni simulate', '📋', [stepsBody], 'Ultime 40'));
  }

  function renderValidation(host, report) {
    const body = el('div');
    report.checks.forEach((check) => {
      body.appendChild(el('div.row', {}, [
        el('span', { text: check.passed ? '✅' : '⛔️' }),
        el('span.grow', {}, [
          el('div', { text: check.name, style: { fontWeight: '500', fontSize: '14px' } }),
          el('div.note', { text: check.detail })
        ])
      ]));
    });

    if (report.folds.length) {
      const folds = el('div.rows');
      report.folds.forEach((fold) => {
        folds.appendChild(el('div.row', {}, [
          el('span.grow.note', { text: ui.shortDate(fold.start) + ' → ' + ui.shortDate(fold.end) }),
          el('span', { text: ui.percent(fold.hitRate * 100, 2) + ' vs ' + ui.percent(fold.baselineHitRate * 100, 2),
            style: { color: fold.difference > 0 ? 'var(--high)' : 'var(--low)', fontSize: '13px' } })
        ]));
      });
      body.appendChild(el('p.note', { text: 'Finestre walk-forward', style: { marginTop: '10px', fontWeight: '600' } }));
      body.appendChild(folds);
    }

    host.appendChild(ui.card('Sistema di validazione', '🛡️', [
      el('p', { text: report.verdict,
        style: { fontSize: '14px', fontWeight: report.isEdgeDemonstrated ? '600' : '400',
          color: report.isEdgeDemonstrated ? 'var(--high)' : 'var(--low)' } }),
      body
    ]));
  }

  // -------------------------------------------------------- Confronto

  views.compare = function () {
    let saved = null;
    const selected = {};

    return {
      title: 'Confronto',
      render: function (container) {
        if (saved === null) {
          Lotto.db.loadSavedCombinations().then((rows) => { saved = rows; Lotto.app.refresh(); });
          container.appendChild(ui.progress('Caricamento…'));
          return;
        }

        if (!saved.length) {
          container.appendChild(ui.empty('🔖', 'Nessuna combinazione salvata',
            'Usa il pulsante «Salva» nelle schermate di generazione per raccogliere qui le combinazioni da confrontare.'));
          container.appendChild(ui.disclaimer(Lotto.DISCLAIMER.score, 'ℹ️'));
          return;
        }

        const list = el('div.rows');
        saved.forEach((item) => {
          list.appendChild(el('div.row.tappable', {
            onclick: () => {
              if (selected[item.id]) delete selected[item.id];
              else if (Object.keys(selected).length < 10) selected[item.id] = true;
              Lotto.app.refresh();
            }
          }, [
            el('span', { text: selected[item.id] ? '☑️' : '⬜️' }),
            el('span.grow', {}, [
              el('div', { text: item.numbers.map(ui.pad).join(' – '),
                style: { fontVariantNumeric: 'tabular-nums', fontSize: '14px' } }),
              el('div.note', { text: Lotto.GAMES[item.game].name
                + (item.wheel && item.wheel !== 'all' ? ' · ' + item.wheel : '')
                + ' · ' + ui.shortDate(item.createdAt) })
            ]),
            ui.scoreBadge(item.score)
          ]));
        });
        container.appendChild(ui.card('Combinazioni salvate', '🔖', [
          list,
          el('p.note', { text: 'Selezionate: ' + Object.keys(selected).length + '/10' })
        ]));

        const rows = saved.filter((item) => selected[item.id]);
        if (rows.length) {
          const table = el('div.rows');
          table.appendChild(el('div.row.header', {}, [
            el('span.grow', { text: 'Combinazione' }),
            el('span.num', { text: 'Score', style: { width: '44px' } }),
            el('span.num', { text: 'Freq.', style: { width: '44px' } }),
            el('span.num', { text: 'Rit.', style: { width: '40px' } }),
            el('span.num', { text: 'Equil.', style: { width: '46px' } })
          ]));
          rows.forEach((item) => {
            const components = item.components || {};
            table.appendChild(el('div.row', {}, [
              el('span.grow', { text: item.numbers.map(ui.pad).join(' '),
                style: { fontVariantNumeric: 'tabular-nums', fontSize: '13px' } }),
              el('span.num', { text: String(Math.round(item.score)),
                style: { width: '44px', color: ui.scoreColor(item.score) } }),
              el('span.num', { text: components.frequency !== undefined
                ? String(Math.round(components.frequency)) : '—', style: { width: '44px' } }),
              el('span.num', { text: components.delay !== undefined
                ? String(Math.round(components.delay)) : '—', style: { width: '40px' } }),
              el('span.num', { text: components.balance !== undefined
                ? String(Math.round(components.balance)) : '—', style: { width: '46px' } })
            ]));
          });
          container.appendChild(ui.card('Confronto', '📋', [table],
            'Combinazione · score · frequenza · ritardo · equilibrio'));
        }

        container.appendChild(el('button.btn.ghost', {
          text: 'Elimina tutte le combinazioni salvate',
          onclick: () => {
            Promise.all(saved.map((item) => Lotto.db.deleteSavedCombination(item.id)))
              .then(() => { saved = null; Lotto.app.refresh(); Lotto.app.toast('Combinazioni eliminate.'); });
          }
        }));
        container.appendChild(ui.disclaimer(Lotto.DISCLAIMER.score, 'ℹ️'));
      }
    };
  };
})(typeof self !== 'undefined' ? self : this);
