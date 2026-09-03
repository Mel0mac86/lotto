/* Guscio dell'applicazione: stato condiviso, comunicazione con il worker,
   navigazione fra le schermate. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const ui = Lotto.ui;
  const el = ui.el;

  const state = {
    settings: Lotto.db.loadSettings(),
    counts: { lotto: 0, superenalotto: 0 },
    latest: { lotto: null, superenalotto: null },
    years: { lotto: [], superenalotto: [] },
    drawsLoaded: false,
    stack: [],
    tab: 'dashboard',
    toastTimer: null
  };

  // ------------------------------------------------------------- Worker

  let worker = null;
  let nextRequestId = 1;
  const pending = new Map();

  function ensureWorker() {
    if (worker) return worker;
    worker = new Worker('js/worker.js');
    worker.onmessage = (event) => {
      const message = event.data || {};
      const entry = pending.get(message.id);
      if (!entry) return;
      if (message.type === 'progress') {
        if (entry.onProgress) entry.onProgress(message.value);
        return;
      }
      pending.delete(message.id);
      if (message.type === 'error') entry.reject(new Error(message.error));
      else entry.resolve(message.result);
    };
    worker.onerror = (event) => {
      pending.forEach((entry) => entry.reject(new Error(event.message || 'Errore nel motore di calcolo.')));
      pending.clear();
    };
    return worker;
  }

  /** Invia un'operazione al worker e restituisce una Promise. */
  function compute(type, payload, onProgress) {
    const id = nextRequestId += 1;
    ensureWorker().postMessage({ id: id, type: type, payload: payload });
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve: resolve, reject: reject, onProgress: onProgress });
    });
  }

  /** Trasferisce l'archivio al worker: si fa una volta sola, non a ogni analisi. */
  function syncDraws() {
    return Lotto.db.loadAllDraws().then((draws) => {
      state.counts.lotto = draws.filter((draw) => draw.game === 'lotto').length;
      state.counts.superenalotto = draws.length - state.counts.lotto;
      state.latest.lotto = null;
      state.latest.superenalotto = null;
      const years = { lotto: {}, superenalotto: {} };
      draws.forEach((draw) => {
        if (!state.latest[draw.game] || draw.date > state.latest[draw.game]) state.latest[draw.game] = draw.date;
        years[draw.game][new Date(draw.date).getFullYear()] = true;
      });
      state.years.lotto = Object.keys(years.lotto).map(Number).sort((a, b) => b - a);
      state.years.superenalotto = Object.keys(years.superenalotto).map(Number).sort((a, b) => b - a);
      state.drawsLoaded = true;
      return compute('setDraws', { draws: draws });
    });
  }

  function hasData() { return state.counts.lotto > 0 || state.counts.superenalotto > 0; }

  // ------------------------------------------------------- Impostazioni

  function saveSettings() { Lotto.db.saveSettings(state.settings); }

  function defaultFilter(gameId) {
    const game = gameId || state.settings.defaultGame;
    return {
      game: game,
      wheel: Lotto.GAMES[game].usesWheels ? state.settings.defaultWheel : 'all',
      period: state.settings.defaultPeriod
    };
  }

  // ------------------------------------------------------- Navigazione

  const TABS = [
    { id: 'dashboard', name: 'Home', icon: '🏠' },
    { id: 'analysis', name: 'Analisi', icon: '📊' },
    { id: 'generate', name: 'Genera', icon: '🔮' },
    { id: 'lab', name: 'Verifica', icon: '🧪' },
    { id: 'settings', name: 'Dati', icon: '⚙️' }
  ];

  /* Le schermate delle tab sono create una volta sola: ricrearle a ogni
     refresh azzererebbe il loro stato locale (filtri, risultati, "sto caricando"). */
  const tabViews = {};

  function viewForTab(tabId) {
    if (!tabViews[tabId]) tabViews[tabId] = Lotto.views.forTab(tabId);
    return tabViews[tabId];
  }

  /** Apre una schermata impilandola su quella corrente. */
  function push(view) {
    state.stack.push(view);
    render();
    window.scrollTo(0, 0);
  }

  function pop() {
    state.stack.pop();
    render();
  }

  function selectTab(tabId) {
    state.tab = tabId;
    state.stack = [];
    render();
    window.scrollTo(0, 0);
  }

  function toast(message, isError) {
    const container = document.getElementById('toast-host');
    ui.clear(container);
    container.appendChild(el('div.toast' + (isError ? '.error' : ''), { text: message }));
    if (state.toastTimer) clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => ui.clear(container), isError ? 6000 : 3200);
  }

  // ------------------------------------------------------------ Render

  function render() {
    const appNode = document.getElementById('app');
    ui.clear(appNode);

    const current = state.stack.length ? state.stack[state.stack.length - 1] : null;
    const view = current || viewForTab(state.tab);

    const bar = el('div.topbar');
    if (current) {
      bar.appendChild(el('button.back', { onclick: pop }, [el('span', { text: '‹' }), el('span', { text: 'Indietro' })]));
    }
    bar.appendChild(el('h1', { text: view.title }));
    if (view.action) bar.appendChild(view.action());
    appNode.appendChild(bar);

    const main = el('main');
    appNode.appendChild(main);
    view.render(main);

    // La barra resta visibile anche nelle schermate di dettaglio, come nelle app iOS:
    // il pulsante «Indietro» risale la pila, la barra cambia sezione.
    appNode.appendChild(tabBar());
  }

  function tabBar() {
    const bar = el('div.tabbar');
    TABS.forEach((tab) => {
      bar.appendChild(el('button', {
        'aria-selected': tab.id === state.tab ? 'true' : 'false',
        onclick: () => selectTab(tab.id)
      }, [el('span.icon', { text: tab.icon }), el('span', { text: tab.name })]));
    });
    return bar;
  }

  /** Sostituisce il contenuto della schermata corrente senza ricostruire la barra. */
  function refresh() {
    const main = document.querySelector('main');
    if (!main) return render();
    const current = state.stack.length ? state.stack[state.stack.length - 1] : viewForTab(state.tab);
    ui.clear(main);
    current.render(main);
  }

  // ---------------------------------------------------------- Avvio

  function acceptDisclaimer() {
    state.settings.acceptedDisclaimer = true;
    saveSettings();
    boot();
  }

  function welcomeScreen() {
    const appNode = document.getElementById('app');
    ui.clear(appNode);
    const main = el('main');
    main.appendChild(el('div', { style: { marginBottom: '18px' } }, [
      el('h1', { text: 'Lotto AI Analyzer', style: { fontSize: '28px', margin: '10px 0 4px' } }),
      el('p', { text: 'Motore di analisi statistica per Lotto e SuperEnalotto',
        style: { color: 'var(--text-secondary)', margin: 0 } })
    ]));

    main.appendChild(ui.card('Che cosa fa questa app', 'ℹ️', [
      el('ul.reasons', {}, [
        'Importa e archivia lo storico delle estrazioni sul dispositivo.',
        'Calcola frequenze, ritardi, co-occorrenze, distribuzioni e trend.',
        'Genera combinazioni con un indice statistico e ne spiega le motivazioni.',
        'Verifica ogni strategia con backtest walk-forward, Monte Carlo e test statistici.'
      ].map((text) => el('li', { text: text })))
    ]));

    main.appendChild(ui.card('Che cosa NON fa', '⚠️', [
      el('ul.reasons', {}, [
        'Non prevede l’estrazione successiva.',
        'Non aumenta la probabilità matematica di vincita.',
        'Non presenta l’indice statistico come una probabilità di uscita.'
      ].map((text) => el('li', { text: text })))
    ]));

    main.appendChild(ui.disclaimer());
    main.appendChild(el('button.btn', { text: 'Ho capito, iniziamo', onclick: acceptDisclaimer }));
    appNode.appendChild(main);
  }

  /**
   * AGGIORNAMENTO AUTOMATICO. All'avvio confronta la data dell'ultima estrazione
   * in archivio con quella pubblicata nel manifesto e, se ne sono uscite di
   * nuove, le importa da sé.
   *
   * Non parte su un archivio vuoto: quello è un primo caricamento, e lo decide
   * l'utente. Se la rete non c'è, si tace: l'app funziona lo stesso con quello
   * che ha già sul dispositivo.
   */
  function checkForNewDraws() {
    if (!state.settings.autoUpdate || !hasData()) return Promise.resolve(null);
    return Lotto.archive.checkForUpdates(state.latest)
      .then((outcome) => {
        if (!outcome || !outcome.updated.length) return null;
        return syncDraws().then(() => {
          refresh();
          const total = outcome.updated.reduce((sum, item) => sum + item.inserted, 0);
          const games = outcome.updated.map((item) => Lotto.GAMES[item.game].name).join(' e ');
          toast('Nuova estrazione analizzata. ' + total + ' estrazioni di '
            + games + ' aggiunte all’archivio.');
          return outcome;
        });
      })
      .catch(() => null);
  }

  function boot() {
    if (!state.settings.acceptedDisclaimer) {
      welcomeScreen();
      return;
    }
    render();
    syncDraws()
      .then(() => refresh())
      .then(() => checkForNewDraws())
      .catch((error) => {
        toast('Archivio non disponibile: ' + error.message, true);
      });
  }

  Lotto.app = {
    state: state,
    compute: compute,
    syncDraws: syncDraws,
    hasData: hasData,
    saveSettings: saveSettings,
    defaultFilter: defaultFilter,
    push: push,
    pop: pop,
    viewForTab: viewForTab,
    refresh: refresh,
    render: render,
    toast: toast,
    boot: boot,
    checkForNewDraws: checkForNewDraws,
    TABS: TABS
  };

  document.addEventListener('DOMContentLoaded', () => {
    boot();
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('sw.js').catch(() => {
        // L'app funziona comunque: senza service worker manca solo l'uso offline.
      });
    }
  });
})(typeof self !== 'undefined' ? self : this);
