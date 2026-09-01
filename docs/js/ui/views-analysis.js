/* Schermate di analisi: statistiche, dettaglio numero, ritardatari,
   caldi/freddi, pattern, Monte Carlo e machine learning. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const ui = Lotto.ui;
  const el = ui.el;
  const views = Lotto.views = Lotto.views || {};
  const charts = Lotto.charts;

  // --------------------------------------------------------- Analisi

  views.analysis = function (gameId) {
    const filter = Lotto.app.defaultFilter(gameId);
    let mode = 'period';
    let selectedYear = null;

    return {
      title: 'Analisi ' + Lotto.GAMES[filter.game].name,
      render: function (container) {
        if (views.requireData(container, filter.game)) return;

        container.appendChild(ui.segmented([
          { id: 'period', name: 'Periodo' },
          { id: 'year', name: 'Anno' }
        ], mode, (selected) => { mode = selected; Lotto.app.refresh(); }));

        container.appendChild(views.filterControls(filter, () => Lotto.app.refresh(),
          { game: false, period: mode === 'period' }));

        const years = Lotto.app.state.years[filter.game];
        if (mode === 'year') {
          if (!years.length) {
            container.appendChild(el('p.note', { text: 'Nessun anno disponibile.' }));
            return;
          }
          if (selectedYear === null) selectedYear = years[0];
          container.appendChild(ui.chips(years.map((year) => ({ id: String(year), name: String(year) })),
            String(selectedYear), (value) => { selectedYear = Number(value); Lotto.app.refresh(); }));
        }

        const activeFilter = Object.assign({}, filter);
        if (mode === 'year') activeFilter.calendarYear = selectedYear;

        views.asyncPanel(container, 'Calcolo statistiche…',
          (onProgress) => Lotto.app.compute('analyze',
            { filter: activeFilter, weights: Lotto.app.state.settings.weights }, onProgress),
          (host, result) => renderAnalysis(host, result.summary, activeFilter));
      }
    };
  };

  function renderAnalysis(host, summary, filter) {
    if (!summary.drawCount) {
      host.appendChild(ui.empty('📭', 'Nessuna estrazione nel periodo',
        'Prova ad allargare il periodo o a scegliere un’altra ruota.'));
      return;
    }

    const sortedByFrequency = summary.numbers.slice().sort((a, b) => b.occurrences - a.occurrences);
    const sortedByDelay = summary.numbers.slice().sort((a, b) => b.currentDelay - a.currentDelay);

    host.appendChild(ui.card('Periodo analizzato', '📅', [
      ui.metrics([
        ui.metric('Estrazioni', ui.integer(summary.drawCount)),
        ui.metric('Dal', ui.shortDate(summary.firstDate)),
        ui.metric('Al', ui.shortDate(summary.lastDate))
      ]),
      ui.metrics([
        ui.metric('Somma media', ui.decimal(summary.sumMean)),
        ui.metric('Più frequente', ui.pad(sortedByFrequency[0].number)),
        ui.metric('Ritardo max', String(sortedByDelay[0].currentDelay))
      ])
    ]));

    const expected = (summary.drawCount * Lotto.GAMES[filter.game].drawnCount) / 90;
    host.appendChild(ui.card('Frequenza dei numeri', '📊', [
      charts.barChart(summary.numbers.map((item) => ({
        label: String(item.number),
        value: item.occurrences,
        color: ui.scoreColor(item.score)
      })), { height: 180, minWidth: 420, reference: expected }),
      el('p.note', { text: 'La linea tratteggiata è la media attesa in caso di pura casualità.' })
    ], 'Uscite osservate contro la media attesa'));

    host.appendChild(ui.card('Ritardo attuale', '⏳', [
      charts.barChart(summary.numbers.map((item) => ({
        label: String(item.number),
        value: item.currentDelay,
        color: item.currentDelay > item.averageDelay * 1.5 ? 'var(--low)' : 'var(--text-secondary)'
      })), { height: 150, minWidth: 420 })
    ], 'Estrazioni trascorse dall’ultima uscita'));

    // Distribuzione delle somme raggruppata per decine.
    const sumBuckets = {};
    summary.sums.forEach((value) => {
      const bucket = Math.floor(value / 10) * 10;
      sumBuckets[bucket] = (sumBuckets[bucket] || 0) + 1;
    });
    host.appendChild(ui.card('Distribuzione delle somme', '➕', [
      charts.barChart(Object.keys(sumBuckets).map(Number).sort((a, b) => a - b).map((bucket) => ({
        label: String(bucket), value: sumBuckets[bucket]
      })), { height: 140, minWidth: 340 })
    ]));

    host.appendChild(ui.card('Pari / dispari per estrazione', '🔵', [
      charts.barChart(Object.keys(summary.evenDistribution).map(Number).sort((a, b) => a - b).map((key) => ({
        label: String(key), value: summary.evenDistribution[key], color: 'var(--medium)'
      })), { height: 130, minWidth: 240 })
    ]));

    host.appendChild(ui.card('Decine e unità', '🔢', [
      charts.barChart([0, 1, 2, 3, 4, 5, 6, 7, 8].map((decade) => ({
        label: (decade * 10 + 1) + '–' + (decade * 10 + 10),
        value: summary.decadeDistribution[decade] || 0,
        color: 'var(--high)'
      })), { height: 140, minWidth: 340 }),
      charts.barChart([0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((unit) => ({
        label: String(unit), value: summary.unitDistribution[unit] || 0
      })), { height: 120, minWidth: 240 })
    ]));

    if (filter.wheel === 'all' && Lotto.GAMES[filter.game].usesWheels) {
      const wheels = Object.keys(summary.byWheel);
      if (wheels.length) {
        const columns = [];
        for (let n = 1; n <= 90; n += 1) columns.push(n);
        const rows = wheels.sort().map((wheel) => {
          const counts = summary.byWheel[wheel];
          let maximum = 1;
          Object.keys(counts).forEach((key) => { if (counts[key] > maximum) maximum = counts[key]; });
          return { label: Lotto.wheelCode(wheel), counts: counts, maximum: maximum };
        });
        host.appendChild(ui.card('Heatmap ruote × numeri', '🗺️', [
          charts.heatmap(rows, columns, (row, number) => (row.counts[number] || 0) / row.maximum)
        ], 'Intensità relativa delle uscite'));
      }
    }

    host.appendChild(numbersTable(summary, filter));
    host.appendChild(ui.disclaimer());
  }

  function numbersTable(summary, filter) {
    let sortField = 'score';
    const card = ui.card('Tabella completa', '📋', [],
      'Numero · uscite · frequenza · ritardo · percentile · indice');
    const body = el('div');

    function draw() {
      ui.clear(body);
      const rows = summary.numbers.slice();
      if (sortField === 'score') rows.sort((a, b) => b.score - a.score);
      else if (sortField === 'occurrences') rows.sort((a, b) => b.occurrences - a.occurrences);
      else if (sortField === 'delay') rows.sort((a, b) => b.currentDelay - a.currentDelay);
      else rows.sort((a, b) => a.number - b.number);

      const list = el('div.rows');
      list.appendChild(el('div.row.header', {}, [
        el('span', { text: 'N.', style: { width: '28px' } }),
        el('span.grow', { text: 'Uscite' }),
        el('span.num', { text: 'Freq.', style: { width: '52px' } }),
        el('span.num', { text: 'Rit.', style: { width: '40px' } }),
        el('span.num', { text: 'Indice', style: { width: '46px' } })
      ]));
      rows.forEach((item) => {
        list.appendChild(el('div.row.tappable', {
          onclick: () => Lotto.app.push(views.numberDetail(item.number, filter))
        }, [
          el('span', { text: ui.pad(item.number), style: { width: '28px', fontWeight: '600' } }),
          el('span.grow', { text: String(item.occurrences) }),
          el('span.num', { text: ui.decimal(item.frequency * 100, 2), style: { width: '52px' } }),
          el('span.num', { text: String(item.currentDelay), style: { width: '40px' } }),
          el('span.num', { text: String(Math.round(item.score)),
            style: { width: '46px', color: ui.scoreColor(item.score), fontWeight: '600' } })
        ]));
      });
      body.appendChild(list);
    }

    card.appendChild(ui.segmented([
      { id: 'score', name: 'Indice' },
      { id: 'occurrences', name: 'Uscite' },
      { id: 'delay', name: 'Ritardo' },
      { id: 'number', name: 'Numero' }
    ], sortField, (selected) => { sortField = selected; draw(); }));
    card.appendChild(body);
    draw();
    return card;
  }

  // ------------------------------------------------- Dettaglio numero

  views.numberDetail = function (number, filter) {
    return {
      title: 'Numero ' + ui.pad(number),
      render: function (container) {
        views.asyncPanel(container, 'Calcolo…',
          (onProgress) => Lotto.app.compute('numberDetail',
            { filter: filter, number: number, weights: Lotto.app.state.settings.weights }, onProgress),
          (host, result) => {
            const stats = result.statistics;
            const score = result.score ? result.score.score : 0;

            host.appendChild(ui.card(null, null, [
              el('div', { style: { display: 'flex', gap: '14px', alignItems: 'center' } }, [
                ui.ball(number, score, 'lg'),
                el('div', {}, [
                  ui.scoreBadge(score),
                  el('p.note', { text: result.summary.description, style: { margin: '6px 0 0' } })
                ])
              ])
            ]));

            host.appendChild(ui.card('Indicatori', '📈', [
              ui.metrics([
                ui.metric('Uscite', String(stats.occurrences), 'su ' + result.summary.drawCount),
                ui.metric('Frequenza', ui.percent(stats.frequency * 100, 2),
                  'attesa ' + ui.percent(stats.expectedFrequency * 100, 2)),
                ui.metric('Percentile', ui.decimal(stats.frequencyPercentile, 0))
              ]),
              ui.metrics([
                ui.metric('Ritardo', String(stats.currentDelay)),
                ui.metric('Ritardo medio', ui.decimal(stats.averageDelay)),
                ui.metric('Ritardo max', String(stats.maxDelay))
              ]),
              ui.barRow('Ritardo attuale / massimo storico', Math.min(stats.delayRatio * 100, 100))
            ]));

            if (result.score && result.score.components) {
              const bars = el('div');
              Lotto.labelledComponents(result.score.components)
                .filter((item) => item.key !== 'balance')
                .forEach((item) => bars.appendChild(ui.barRow(item.label, item.value)));
              host.appendChild(ui.card('Scomposizione dell’indice', '🎚️', [bars]));
            }

            const yearRows = Object.keys(result.byYear).map(Number).sort((a, b) => a - b)
              .map((year) => ({ label: String(year), value: result.byYear[year][number] || 0 }));
            if (yearRows.length) {
              host.appendChild(ui.card('Uscite per anno', '📅', [
                charts.barChart(yearRows, { height: 150, minWidth: 260 })
              ]));
            }

            const monthNames = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
            const monthRows = [];
            for (let month = 1; month <= 12; month += 1) {
              monthRows.push({
                label: monthNames[month - 1],
                value: (result.byMonth[month] || {})[number] || 0,
                color: 'var(--medium)'
              });
            }
            host.appendChild(ui.card('Uscite per mese', '🗓️', [
              charts.barChart(monthRows, { height: 140, minWidth: 300 })
            ], 'Aggregato su tutto il periodo selezionato'));

            if (result.partners.length) {
              const rows = el('div.rows');
              result.partners.forEach((partner) => {
                rows.appendChild(el('div.row', {}, [
                  ui.ball(partner.number, undefined, 'sm'),
                  el('span.grow', {}, [
                    el('div', { text: partner.count + ' uscite congiunte' }),
                    el('div.note', { text: partner.lift >= 1
                      ? ui.decimal((partner.lift - 1) * 100, 0) + '% sopra l’atteso'
                      : ui.decimal((1 - partner.lift) * 100, 0) + '% sotto l’atteso' })
                  ]),
                  el('span.num', { text: ui.decimal(partner.lift, 2),
                    style: { color: partner.lift > 1.15 ? 'var(--high)' : 'var(--text-secondary)' } })
                ]));
              });
              host.appendChild(ui.card('Numeri più ricorrenti insieme', '🔗', [rows]));
            }

            host.appendChild(ui.card('Lettura in linguaggio naturale', '💬', [
              el('p.pre-wrap', { text: result.explanation })
            ]));
            host.appendChild(ui.disclaimer(Lotto.DISCLAIMER.delay, '⏳'));
          });
      }
    };
  };

  // ------------------------------------------------------ Ritardatari

  views.delays = function (gameId) {
    const filter = Lotto.app.defaultFilter(gameId);
    return {
      title: 'Ritardatari',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;
        container.appendChild(views.filterControls(filter, () => Lotto.app.refresh(), { game: false }));

        views.asyncPanel(container, 'Calcolo dei ritardi…',
          (onProgress) => Lotto.app.compute('analyze',
            { filter: filter, weights: Lotto.app.state.settings.weights }, onProgress),
          (host, result) => {
            const summary = result.summary;
            const sorted = summary.numbers.slice().sort((a, b) => b.currentDelay - a.currentDelay);

            host.appendChild(ui.card('Ritardo attuale rispetto al massimo storico', '📊', [
              charts.horizontalBars(sorted.slice(0, 20).map((item) => ({
                label: ui.pad(item.number),
                value: Math.min(item.delayRatio * 100, 100),
                caption: item.currentDelay + '/' + item.maxDelay,
                color: ui.scoreColor(Math.min(item.delayRatio * 100, 100))
              })), { max: 100 }),
              el('p.note', { text: 'La barra indica quanto il ritardo attuale si avvicina al massimo storico del numero.' })
            ]));

            const rows = el('div.rows');
            rows.appendChild(el('div.row.header', {}, [
              el('span', { text: 'N.', style: { width: '28px' } }),
              el('span.grow', { text: 'Ultima uscita' }),
              el('span.num', { text: 'Rit.', style: { width: '40px' } }),
              el('span.num', { text: 'Medio', style: { width: '46px' } }),
              el('span.num', { text: 'Max', style: { width: '40px' } })
            ]));
            sorted.forEach((item) => {
              rows.appendChild(el('div.row.tappable', {
                onclick: () => Lotto.app.push(views.numberDetail(item.number, filter))
              }, [
                el('span', { text: ui.pad(item.number), style: { width: '28px', fontWeight: '600' } }),
                el('span.grow', { text: item.lastSeen ? ui.shortDate(item.lastSeen) : 'mai' }),
                el('span.num', { text: String(item.currentDelay), style: { width: '40px' } }),
                el('span.num', { text: ui.decimal(item.averageDelay), style: { width: '46px' } }),
                el('span.num', { text: String(item.maxDelay), style: { width: '40px' } })
              ]));
            });
            host.appendChild(ui.card('Tutti i numeri', '📋', [rows], 'Ordinati per ritardo attuale'));
            host.appendChild(ui.disclaimer(Lotto.DISCLAIMER.delay, '⚠️'));
          });
      }
    };
  };

  // ------------------------------------------------------ Caldi/freddi

  views.hotCold = function (gameId, initial) {
    const filter = Lotto.app.defaultFilter(gameId);
    let temperature = initial || 'hot';
    return {
      title: 'Hot / Cold',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;
        container.appendChild(views.filterControls(filter, () => Lotto.app.refresh(), { game: false }));
        container.appendChild(ui.chips(Lotto.TEMPERATURES, temperature,
          (selected) => { temperature = selected; Lotto.app.refresh(); }));

        views.asyncPanel(container, 'Calcolo…',
          (onProgress) => Lotto.app.compute('analyze',
            { filter: filter, weights: Lotto.app.state.settings.weights }, onProgress),
          (host, result) => {
            const definition = Lotto.TEMPERATURES.find((item) => item.id === temperature);
            const entries = filterByTemperature(result.summary.numbers, temperature).slice(0, 30);

            const rows = el('div.rows');
            if (!entries.length) {
              rows.appendChild(el('p.note', { text: 'Nessun numero rientra in questo criterio nel periodo selezionato.' }));
            }
            entries.forEach((item) => {
              rows.appendChild(el('div.row.tappable', {
                onclick: () => Lotto.app.push(views.numberDetail(item.number, filter))
              }, [
                ui.ball(item.number, item.score, 'sm'),
                el('span.grow', {}, [
                  el('div', { text: item.tags.join('  '), style: { fontSize: '12px' } }),
                  el('div.note', { text: item.occurrences + ' uscite · ritardo ' + item.currentDelay
                    + ' · trend ' + ui.decimal(item.trendRatio, 2) + '×' })
                ]),
                ui.scoreBadge(item.score)
              ]));
            });
            host.appendChild(ui.card(definition.name, '🌡️', [rows], definition.description));

            host.appendChild(ui.card('Trend: frequenza recente / frequenza del periodo', '📈', [
              charts.barChart(result.summary.numbers.map((item) => ({
                label: String(item.number),
                value: Math.max(item.trendRatio, 0),
                color: item.trendRatio >= 1 ? 'var(--high)' : 'var(--low)'
              })), { height: 160, minWidth: 420, reference: 1 }),
              el('p.note', { text: 'La linea tratteggiata è il valore 1,0: nessuna variazione. Su estrazioni casuali queste oscillazioni sono normali.' })
            ]));
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  function filterByTemperature(numbers, temperature) {
    const isHot = (item) => item.trendRatio >= 1.10;
    const isCold = (item) => item.trendRatio <= 0.90;
    const isOverdue = (item) => item.averageDelay > 0 && item.currentDelay > item.averageDelay * 1.5;

    let matching = numbers.filter((item) => {
      switch (temperature) {
        case 'hot': return isHot(item);
        case 'cold': return isCold(item);
        case 'overdue': return isOverdue(item);
        case 'hotOverdue': return isHot(item) && isOverdue(item);
        case 'coldOverdue': return isCold(item) && isOverdue(item);
        case 'hotRecent': return isHot(item) && item.currentDelay <= Math.max(Math.floor(item.averageDelay / 2), 3);
        default: return !isHot(item) && !isCold(item) && !isOverdue(item);
      }
    });
    if (!matching.length) matching = numbers.slice();

    return matching.sort((a, b) => {
      if (temperature === 'hot' || temperature === 'hotRecent') return b.trendRatio - a.trendRatio;
      if (temperature === 'cold') return a.trendRatio - b.trendRatio;
      if (temperature === 'overdue' || temperature === 'hotOverdue' || temperature === 'coldOverdue') {
        return b.currentDelay - a.currentDelay;
      }
      return b.score - a.score;
    });
  }

  // ---------------------------------------------------------- Pattern

  views.patterns = function () {
    const filter = Lotto.app.defaultFilter();
    let started = false;
    return {
      title: 'Trova pattern',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;
        container.appendChild(ui.card(null, null, [
          views.filterControls(filter, () => { started = false; Lotto.app.refresh(); }),
          el('button.btn', { text: '🔍 Trova pattern', onclick: () => { started = true; Lotto.app.refresh(); } })
        ]));

        if (!started) {
          container.appendChild(ui.empty('🔍', 'Nessuna ricerca eseguita',
            'Scegli gioco, ruota e periodo, poi avvia la ricerca.'));
          // Un pattern vero, già trovato su tutto l'archivio: vale la pena
          // mostrarlo prima ancora che l'utente avvii una ricerca sua.
          const archive = el('div');
          container.appendChild(archive);
          Lotto.patternArchive.load().then((data) => {
            if (data && data.scoperta) archivePatternCards(archive, data);
          });
          container.appendChild(ui.disclaimer());
          return;
        }

        views.asyncPanel(container, 'Ricerca di pattern…',
          (onProgress) => Lotto.app.compute('patterns',
            { filter: filter, weights: Lotto.app.state.settings.weights }, onProgress),
          (host, result) => {
            const noteworthy = result.patterns.filter((item) => item.isNoteworthy).length;
            host.appendChild(ui.card('Sintesi', '📋', [
              ui.metrics([
                ui.metric('Pattern esaminati', String(result.patterns.length)),
                ui.metric('Da approfondire', String(noteworthy), null,
                  noteworthy > 0 ? 'var(--medium)' : 'var(--high)')
              ]),
              el('p.note', { text: noteworthy === 0
                ? 'Nessun pattern si discosta dalla casualità in modo statisticamente rilevante.'
                : 'Alcuni pattern superano le soglie di significatività. Ricorda che, testando migliaia di combinazioni, alcuni scostamenti compaiono per puro caso.' })
            ]));

            Lotto.PATTERN_CATEGORIES.forEach((category) => {
              const items = result.patterns.filter((item) => item.category === category.id);
              if (!items.length) return;
              const body = el('div');
              items.forEach((pattern) => {
                body.appendChild(el('div', { style: { padding: '8px 0', borderTop: '1px solid var(--separator)' } }, [
                  el('div', { style: { display: 'flex', gap: '8px' } }, [
                    el('span.grow', { text: pattern.title, style: { fontWeight: '600', fontSize: '14px' } }),
                    pattern.isNoteworthy
                      ? el('span', { text: 'da approfondire', style: { fontSize: '11px', color: 'var(--medium)' } })
                      : null
                  ]),
                  el('p.pre-wrap', { text: pattern.detail, style: { fontSize: '13px', margin: '4px 0' } }),
                  pattern.test ? el('p.note', { text: 'Statistica: ' + ui.decimal(pattern.test.statistic, 2)
                    + (pattern.test.degreesOfFreedom ? ' · gdl ' + pattern.test.degreesOfFreedom : '')
                    + ' · p = ' + Lotto.formatP(pattern.test.pValue) }) : null,
                  el('p.note', { text: pattern.assessment })
                ]));
              });
              host.appendChild(ui.card(category.name, category.icon, [body]));
            });
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  // ------------------------------------------------------ Monte Carlo

  views.monteCarlo = function () {
    const filter = Lotto.app.defaultFilter();
    let iterations = 100000;
    let started = false;

    return {
      title: 'Monte Carlo',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;

        container.appendChild(ui.card('Configurazione', '🎚️', [
          views.filterControls(filter, () => { started = false; Lotto.app.refresh(); }),
          ui.segmented([
            { id: '100000', name: '100.000' },
            { id: '500000', name: '500.000' },
            { id: '1000000', name: '1.000.000' }
          ], String(iterations), (value) => { iterations = Number(value); started = false; Lotto.app.refresh(); }),
          el('button.btn', { text: 'Avvia simulazione', onclick: () => { started = true; Lotto.app.refresh(); } })
        ]));

        if (!started) {
          container.appendChild(ui.disclaimer(Lotto.DISCLAIMER.monteCarlo, '🎲'));
          return;
        }

        views.asyncPanel(container, 'Simulazione in corso…',
          (onProgress) => Lotto.app.compute('monteCarlo',
            { filter: filter, iterations: iterations, weights: Lotto.app.state.settings.weights }, onProgress),
          (host, payload) => {
            const result = payload.result;
            host.appendChild(ui.card('Conclusione', '✅', [
              el('p', { text: result.conclusion, style: { fontSize: '14px' } }),
              el('p.note', { text: 'Simulazione di ' + ui.integer(result.iterations)
                + ' estrazioni completata in ' + ui.decimal(result.elapsed, 2) + ' secondi.' })
            ]));

            const testsBody = el('div');
            result.tests.forEach((test) => {
              testsBody.appendChild(el('div', { style: { padding: '7px 0', borderTop: '1px solid var(--separator)' } }, [
                el('div', { style: { display: 'flex', gap: '8px' } }, [
                  el('span.grow', { text: test.name, style: { fontSize: '14px', fontWeight: '500' } }),
                  el('span', { text: test.isSignificant ? 'scostamento' : 'compatibile',
                    style: { fontSize: '11px', fontWeight: '600',
                      color: test.isSignificant ? 'var(--low)' : 'var(--high)' } })
                ]),
                el('p.note', { text: test.interpretation })
              ]));
            });
            host.appendChild(ui.card('Test statistici sui dati storici', 'ƒ', [testsBody]));

            host.appendChild(ui.card('Frequenza per numero', '📊', [
              charts.barChart(payload.summary.numbers.map((item) => ({
                label: String(item.number),
                value: (result.historicalFrequency[item.number] || 0) * 100
              })), { height: 170, minWidth: 420,
                reference: (Lotto.GAMES[filter.game].drawnCount / 90) * 100 }),
              el('p.note', { text: 'La linea tratteggiata è la frequenza prodotta dalla simulazione puramente casuale.' })
            ], 'Storico contro simulazione casuale'));

            host.appendChild(comparisonCard('Distribuzione delle somme',
              bucketize(result.historicalSums, 10), bucketize(result.simulatedSums, 10)));
            host.appendChild(comparisonCard('Distribuzione pari/dispari',
              toPercentMap(result.historicalEven), toPercentMap(result.simulatedEven)));
            host.appendChild(comparisonCard('Distribuzione per decine',
              toPercentMap(result.historicalDecades), toPercentMap(result.simulatedDecades),
              (key) => (Number(key) * 10 + 1) + '–' + (Number(key) * 10 + 10)));

            host.appendChild(ui.disclaimer(Lotto.DISCLAIMER.monteCarlo, '🎲'));
          });
      }
    };
  };

  function bucketize(map, size) {
    const buckets = {};
    let total = 0;
    Object.keys(map).forEach((key) => {
      const bucket = Math.floor(Number(key) / size) * size;
      buckets[bucket] = (buckets[bucket] || 0) + map[key];
      total += map[key];
    });
    Object.keys(buckets).forEach((key) => { buckets[key] = total ? (buckets[key] / total) * 100 : 0; });
    return buckets;
  }

  function toPercentMap(map) {
    let total = 0;
    Object.keys(map).forEach((key) => { total += map[key]; });
    const result = {};
    Object.keys(map).forEach((key) => { result[key] = total ? (map[key] / total) * 100 : 0; });
    return result;
  }

  function comparisonCard(title, historical, simulated, labelFor) {
    const keys = Array.from(new Set(Object.keys(historical).concat(Object.keys(simulated))))
      .map(Number).sort((a, b) => a - b);
    return ui.card(title, '📉', [
      charts.groupedBars(keys.map((key) => ({
        label: labelFor ? labelFor(key) : String(key),
        a: historical[key] || 0,
        b: simulated[key] || 0
      })), { labels: ['Storico', 'Simulato'], height: 170 })
    ]);
  }

  /** Il pattern trovato passando al setaccio tutto l'archivio.

      È vero, verificato e completamente inutile per vincere: raccontarlo
      per intero — compresa l'ultima parte — è il punto. */
  function archivePatternCards(host, data) {
    const finding = data.scoperta;

    const rows = el('div.rows');
    finding.medie.forEach((row) => {
      const anomalous = Math.abs(row.z) > 3;
      rows.appendChild(el('div.row', {}, [
        el('span.grow', {}, [
          el('div', { text: row.periodo, style: { fontWeight: '500' } }),
          el('div.note', { text: ui.integer(row.estrazioni) + ' estrazioni' })
        ]),
        el('span.num', { text: ui.decimal(row.media, 3),
          style: { fontWeight: '600', color: anomalous ? 'var(--low)' : 'var(--text)' } }),
        el('span.note', { text: 'z ' + (row.z > 0 ? '+' : '') + ui.decimal(row.z, 2),
          style: { minWidth: '62px', textAlign: 'right' } })
      ]));
    });

    host.appendChild(ui.card('Un pattern vero, nello storico', '🔎', [
      el('p', { text: finding.titolo, style: { fontSize: '15px', fontWeight: '600' } }),
      el('p.note', { text: 'Media dei numeri estratti. Se le estrazioni fossero perfettamente '
        + 'uniformi varrebbe 45,500 in ogni epoca. Fra il 1970 e il 1999 non lo è: '
        + 'sette deviazioni standard sopra, cioè una probabilità di circa 5 su un milione '
        + 'di miliardi che sia un caso.' }),
      rows,
      el('p.note', { text: 'Prima del 1970 e dopo il 1999 il valore torna dov’è atteso. '
        + 'L’effetto regge separando gli anni pari dai dispari, e va nella stessa direzione '
        + 'su tutte e dieci le ruote dell’epoca.' })
    ]));

    // Dove agiva: sul primo estratto molto più che sull'ultimo.
    const positions = el('div.rows');
    finding.posizioni.forEach((row) => {
      positions.appendChild(el('div.row', {}, [
        el('span.grow.note', { text: row.posizione + '° numero estratto' }),
        el('span', { text: (row.distorta > 0 ? '+' : '') + ui.decimal(row.distorta, 2),
          style: { fontWeight: '600', minWidth: '58px', textAlign: 'right',
            color: row.distorta > 3 ? 'var(--low)' : 'var(--text)' } }),
        el('span.note', { text: (row.pulita > 0 ? '+' : '') + ui.decimal(row.pulita, 2),
          style: { minWidth: '58px', textAlign: 'right' } })
      ]));
    });
    host.appendChild(ui.card('Dove agiva', '🎯', [
      el('p.note', { text: 'Scostamento in deviazioni standard, per posizione di estrazione. '
        + 'A sinistra il periodo 1970-1999, a destra il 2000-2026.' }),
      positions,
      el('p.note', { text: 'La distorsione è forte sul primo numero estratto e si spegne '
        + 'verso l’ultimo. È la firma di qualcosa di fisico nell’estrazione, non di un '
        + 'errore nei dati: un errore non avrebbe motivo di seguire l’ordine di uscita.' })
    ]));

    // E adesso la parte che conta: non serve a niente.
    const rule = el('div.rows');
    finding.regolaFissa.forEach((row) => {
      rule.appendChild(el('div.row', {}, [
        el('span.grow.note', { text: row.periodo }),
        el('span', { text: ui.decimal(row.centriPerEstrazione, 4),
          style: { fontWeight: '600', minWidth: '66px', textAlign: 'right' } }),
        el('span.note', { text: (row.vantaggio > 0 ? '+' : '') + ui.decimal(row.vantaggio, 1) + '%',
          style: { minWidth: '58px', textAlign: 'right',
            color: row.z > 3 ? 'var(--medium)' : 'var(--text-secondary)' } })
      ]));
    });

    const transfer = el('div.rows');
    finding.trasferimento.forEach((row) => {
      transfer.appendChild(el('div.row', {}, [
        el('span.grow', {}, [
          el('div.note', { text: 'scelti sul ' + row.scelti + ', giocati sul ' + row.giocati }),
          el('div', { text: row.numeri.map(ui.pad).join('  '),
            style: { fontSize: '12px', fontVariantNumeric: 'tabular-nums' } })
        ]),
        el('span.note', { text: (row.vantaggio > 0 ? '+' : '') + ui.decimal(row.vantaggio, 1) + '%',
          style: { minWidth: '58px', textAlign: 'right' } })
      ]));
    });

    host.appendChild(ui.card('E adesso la parte scomoda', '⚖️', [
      el('p.note', { text: 'Giocando sempre 86-87-88-89-90 — una regola fissa, decisa senza '
        + 'guardare i dati — si sarebbero centrati questi numeri per estrazione, contro i '
        + ui.decimal(finding.attesaCentri, 4) + ' attesi dal caso:' }),
      rule,
      el('p.note', { text: 'Sei per cento in più, nel periodo giusto. Ma scegliendo i numeri '
        + 'su un periodo e giocandoli su quello successivo — l’unico modo onesto di usarli, '
        + 'perché il futuro non si conosce — il vantaggio evapora:' }),
      transfer,
      el('p', { text: 'Il Lotto restituisce ai giocatori circa il 60-70% del giocato. '
        + 'Per andare in pari servirebbe un vantaggio fra il 43% e il 67%. '
        + 'Il pattern più forte in 87 anni di storia ne vale il 6%, in un’epoca finita '
        + 'da un quarto di secolo.', style: { fontSize: '14px' } }),
      el('p.note', { text: 'Su 48 test, cinque sopravvivono alla correzione per la '
        + 'molteplicità, e descrivono tutti questo stesso effetto. Gli altri quarantatré '
        + 'non trovano nulla.' })
    ]));
  }

  // -------------------------------------------------------- AI Analyst

  views.machineLearning = function () {
    const filter = Lotto.app.defaultFilter();
    let model = 'logisticRegression';
    let started = false;

    return {
      title: 'AI Analyst',
      render: function (container) {
        if (views.requireData(container, filter.game)) return;

        container.appendChild(ui.card('Modulo sperimentale', '🧠', [
          el('p.note', { text: Lotto.DISCLAIMER.machineLearning })
        ]));

        const definition = Lotto.ML_MODELS.find((item) => item.id === model);
        container.appendChild(ui.card('Configurazione', '🎚️', [
          views.filterControls(filter, () => { started = false; Lotto.app.refresh(); }),
          ui.select('Modello', Lotto.ML_MODELS, model, (value) => {
            model = value; started = false; Lotto.app.refresh();
          }),
          el('p.note', { text: definition.purpose }),
          el('button.btn', { text: 'Esegui', onclick: () => { started = true; Lotto.app.refresh(); } })
        ]));

        if (!started) { container.appendChild(ui.disclaimer()); return; }

        // TimesFM non gira nel browser: le previsioni arrivano già calcolate.
        if (model === 'timesfm') {
          views.asyncPanel(container, 'Lettura delle previsioni…',
            () => Lotto.timesfm.load(),
            (host, payload) => {
              if (!payload) {
                host.appendChild(ui.empty('📭', 'Previsioni non disponibili',
                  'Il file delle previsioni di TimesFM non è nel pacchetto di questa versione.'));
              } else {
                timesfmCards(host, payload, filter);
                const eras = el('div');
                host.appendChild(eras);
                Lotto.timesfm.loadEras().then((data) => {
                  if (data) eraExperimentCard(eras, data);
                });
              }
              host.appendChild(ui.disclaimer());
            });
          return;
        }

        views.asyncPanel(container, 'Addestramento e valutazione…',
          (onProgress) => Lotto.app.compute('ml',
            { filter: filter, model: model, weights: Lotto.app.state.settings.weights }, onProgress),
          (host, result) => {
            if (result.evaluation) host.appendChild(evaluationCard(result.evaluation));
            else if (result.clusters) host.appendChild(clustersCard(result.clusters));
            else if (result.anomalies) host.appendChild(anomaliesCard(result.anomalies));
            else if (result.posteriors) host.appendChild(bayesianCard(result.posteriors, result.bayesianSummary));
            else {
              host.appendChild(ui.empty('📉', 'Storico insufficiente',
                'Per addestrare il modello servono almeno alcune centinaia di estrazioni nel periodo selezionato.'));
            }
            host.appendChild(ui.disclaimer());
          });
      }
    };
  };

  /** Le previsioni di TimesFM e, sotto, quanto valgono davvero.
      Le due schede vanno sempre insieme: i numeri da soli direbbero una
      cosa che la misura smentisce. */
  function timesfmCards(host, payload, filter) {
    const wheelName = Lotto.GAMES[filter.game].usesWheels && filter.wheel !== 'all'
      ? filter.wheel : 'Bari';
    const wheel = payload.ruote ? payload.ruote[wheelName] : null;

    // --- I numeri previsti
    if (wheel) {
      const encodings = el('div.rows');
      Object.keys(wheel.perCodifica || {}).forEach((key) => {
        encodings.appendChild(el('div.row', {}, [
          el('span.grow.note', { text: 'Codifica ' + key }),
          el('span', { text: wheel.perCodifica[key].slice(0, 5).map(ui.pad).join('  '),
            style: { fontSize: '13px', fontVariantNumeric: 'tabular-nums' } })
        ]));
      });

      host.appendChild(ui.card('Previsione per ' + wheelName, '🔮', [
        el('p.note', { text: 'Cinquina con il punteggio più alto, dalle ultime '
          + ui.integer(payload.contesto) + ' estrazioni della ruota.' }),
        ui.combinationRow(wheel.cinquina),
        el('p.note', { text: 'I dieci numeri meglio posizionati: '
          + wheel.combinata.map(ui.pad).join('  ') }),
        encodings,
        el('p.note', { text: 'Ultima estrazione vista dal modello: '
          + formatCompactDate(wheel.ultimaEstrazioneVista)
          + ' · previsioni generate il ' + payload.generatoIl + '.' })
      ]));
    }

    // --- Quanto vale la previsione
    const evaluation = payload.valutazione;
    if (!evaluation) return;

    const best = Lotto.timesfm.bestRow(evaluation.reale);
    const baseline = Lotto.timesfm.baselineRow(evaluation.reale);
    const controlBest = Lotto.timesfm.bestRow(evaluation.controllo);

    host.appendChild(ui.card('Quanto vale questa previsione', '🔬', [
      el('p.note', { text: 'Prova walk-forward su ' + ui.integer(evaluation.estrazioniValutate)
        + ' estrazioni della ruota ' + (evaluation.ruota || '') + ': a ogni passo il modello '
        + 'vede soltanto le estrazioni precedenti, poi si contano i centri della cinquina prevista.' }),
      ui.metrics([
        ui.metric('Centri per estrazione', best ? ui.decimal(best.centriPerEstrazione, 3) : '—',
          'TimesFM'),
        ui.metric('Attesi dal caso', ui.decimal(0.2778, 3), '5 numeri su 90'),
        ui.metric('Baseline casuale', baseline ? ui.decimal(baseline.centriPerEstrazione, 3) : '—',
          'stesso numero di giocate')
      ]),
      best ? ui.metrics([
        ui.metric('AUC', ui.decimal(best.auc, 3), '0,500 = casuale',
          best.auc > 0.55 ? 'var(--medium)' : 'var(--high)'),
        ui.metric('p', ui.decimal(best.p, 4), best.significativo ? 'significativo' : 'non significativo')
      ]) : null,
      el('p', {
        text: best && best.significativo
          ? 'Su questo campione la previsione batte il caso in modo statisticamente significativo. Il risultato va replicato su altre ruote e altri periodi prima di considerarlo reale.'
          : Lotto.DISCLAIMER.noEdge + ' La cinquina prevista non centra più numeri di cinque numeri estratti a caso.',
        style: { fontSize: '14px' }
      })
    ]));

    // --- Il controllo che rende leggibile il risultato
    if (controlBest) {
      host.appendChild(ui.card('Controllo: lo stesso modello su dati prevedibili', '🧪', [
        el('p.note', { text: 'La stessa procedura, sulle stesse metriche, applicata a estrazioni '
          + 'inventate e volutamente regolari. Serve a distinguere «il modello non trova nulla» '
          + 'da «la procedura è rotta».' }),
        ui.metrics([
          ui.metric('Centri per estrazione', ui.decimal(controlBest.centriPerEstrazione, 2),
            'su 5 possibili', 'var(--high)'),
          ui.metric('AUC', ui.decimal(controlBest.auc, 3), 'dati regolari', 'var(--high)')
        ]),
        el('p.note', { text: 'Sui dati regolari TimesFM azzecca quasi tutta la cinquina. '
          + 'La procedura funziona: quando c’è qualcosa da prevedere, lo prevede. '
          + 'Sulle estrazioni vere non c’è.' })
      ]));
    }
  }

  /** Il modello messo davanti a un pattern vero: quello del 1970-1999.

      La colonna che conta è la prima, il rumore puro. Senza, il +6,33 della
      colonna di mezzo sembrerebbe una scoperta. */
  function eraExperimentCard(host, data) {
    const encodings = ['binaria', 'ritardo', 'frequenza'];
    const table = el('div');

    table.appendChild(el('div.row', {}, [
      el('span.grow.note', { text: 'codifica', style: { fontWeight: '600' } }),
      ...data.condizioni.map((condition) => el('span.note', {
        text: condition.patternVero ? 'pattern vero' : 'nessun pattern',
        style: { minWidth: '72px', textAlign: 'right', fontWeight: '600',
          color: condition.patternVero ? 'var(--accent)' : 'var(--text-secondary)' }
      }))
    ]));
    table.appendChild(el('div.row', {}, [
      el('span.grow.note', { text: '' }),
      ...data.condizioni.map((condition) => el('span.note', {
        text: condition.periodo === 'nessuno' ? 'casuali' : condition.periodo,
        style: { minWidth: '72px', textAlign: 'right', fontSize: '11px' }
      }))
    ]));

    encodings.forEach((key) => {
      table.appendChild(el('div.row', {}, [
        el('span.grow.note', { text: key }),
        ...data.condizioni.map((condition) => {
          const row = condition.codifiche[key];
          return el('span', {
            text: (row.correlazioneConIlValore > 0 ? '+' : '')
              + ui.decimal(row.correlazioneConIlValore, 3),
            style: { minWidth: '72px', textAlign: 'right', fontSize: '13px',
              fontVariantNumeric: 'tabular-nums' }
          });
        })
      ]));
    });

    host.appendChild(ui.card('Il modello davanti a un pattern vero', '🧭', [
      el('p.note', { text: data.domanda }),
      el('p.note', { text: 'Correlazione fra il punteggio che il modello assegna a un numero '
        + 'e il valore del numero stesso. Nel 1970-1999 i numeri alti uscivano davvero di '
        + 'più: se il modello se ne accorgesse, qui si vedrebbe.' }),
      table,
      el('p', { text: data.conclusione, style: { fontSize: '14px' } }),
      el('p.note', { text: data.avvertenza })
    ]));
  }

  function formatCompactDate(value) {
    if (!value || value.length !== 8) return value || '—';
    return value.slice(6, 8) + '/' + value.slice(4, 6) + '/' + value.slice(0, 4);
  }

  function evaluationCard(evaluation) {
    return ui.card(evaluation.modelName, '🧠', [
      ui.metrics([
        ui.metric('Campioni train', ui.integer(evaluation.trainingSamples)),
        ui.metric('Campioni test', ui.integer(evaluation.testSamples))
      ]),
      ui.metrics([
        ui.metric('AUC', ui.decimal(evaluation.auc, 3), '0,500 = casuale',
          evaluation.auc > 0.55 ? 'var(--medium)' : 'var(--high)'),
        ui.metric('Accuratezza', ui.percent(evaluation.accuracy * 100, 2)),
        ui.metric('Baseline', ui.percent(evaluation.baselineAccuracy * 100, 2))
      ]),
      ui.metrics([
        ui.metric('Log loss', ui.decimal(evaluation.logLoss, 4)),
        ui.metric('Log loss baseline', ui.decimal(evaluation.baselineLogLoss, 4))
      ]),
      el('p', { text: evaluation.verdict, style: { fontSize: '14px' } }),
      el('p.note', { text: evaluation.significance.interpretation }),
      el('p.note', { text: 'Lo split fra addestramento e test è temporale: il modello viene valutato solo su estrazioni successive a quelle su cui è stato addestrato.' })
    ]);
  }

  function clustersCard(clusters) {
    const body = el('div');
    clusters.forEach((cluster) => {
      body.appendChild(el('div', { style: { padding: '8px 0', borderTop: '1px solid var(--separator)' } }, [
        el('div', { style: { display: 'flex' } }, [
          el('span.grow', { text: cluster.title, style: { fontWeight: '600', fontSize: '14px' } }),
          el('span.note', { text: cluster.numbers.length + ' numeri' })
        ]),
        el('p.note', { text: cluster.profile }),
        el('p', { text: cluster.numbers.map(ui.pad).join('  '),
          style: { fontSize: '12px', fontVariantNumeric: 'tabular-nums' } })
      ]));
    });
    return ui.card('Clustering dei numeri', '🧩', [body,
      el('p.note', { text: 'Il clustering descrive somiglianze fra profili storici. Gruppi simili emergono anche da dati puramente casuali.' })]);
  }

  function anomaliesCard(anomalies) {
    const rows = el('div.rows');
    anomalies.forEach((item) => {
      rows.appendChild(el('div.row', {}, [
        ui.ball(item.number, undefined, 'sm'),
        el('span.grow', {}, [
          el('div', { text: 'Distanza dal profilo medio: ' + ui.decimal(item.distance, 2),
            style: { fontSize: '13px' } }),
          el('div.note', { text: item.explanation })
        ])
      ]));
    });
    return ui.card('Numeri con profilo più atipico', '⚠️', [rows]);
  }

  function bayesianCard(posteriors, summary) {
    return ui.card('Probabilità a posteriori', 'ƒ', [
      el('p', { text: summary, style: { fontSize: '14px' } }),
      charts.barChart(posteriors.map((item) => ({
        label: String(item.number),
        value: Math.abs(item.deviationPercent),
        color: item.containsTheoretical ? 'var(--high)' : 'var(--low)'
      })), { height: 170, minWidth: 420 }),
      el('p.note', { text: 'Scostamento percentuale (in valore assoluto) della media a posteriori rispetto alla probabilità teorica. In rosso i numeri il cui intervallo di credibilità al 95% non contiene il valore teorico.' })
    ]);
  }
})(typeof self !== 'undefined' ? self : this);
