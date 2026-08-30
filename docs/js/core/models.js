/* Modelli di dominio: giochi, ruote, periodi di analisi, pesi dello scoring
   e i testi delle avvertenze. Rispecchia la cartella Models/ del progetto Swift. */
(function (root) {
  'use strict';

  const GAMES = {
    lotto: {
      id: 'lotto',
      name: 'Lotto',
      symbol: '🎱',
      drawnCount: 5,
      usesWheels: true,
      usesJolly: false,
      usesSuperStar: false
    },
    superenalotto: {
      id: 'superenalotto',
      name: 'SuperEnalotto',
      symbol: '⭐️',
      drawnCount: 6,
      usesWheels: false,
      usesJolly: true,
      usesSuperStar: true
    }
  };

  const WHEELS = [
    { id: 'Bari', code: 'BA' },
    { id: 'Cagliari', code: 'CA' },
    { id: 'Firenze', code: 'FI' },
    { id: 'Genova', code: 'GE' },
    { id: 'Milano', code: 'MI' },
    { id: 'Napoli', code: 'NA' },
    { id: 'Palermo', code: 'PA' },
    { id: 'Roma', code: 'RM' },
    { id: 'Torino', code: 'TO' },
    { id: 'Venezia', code: 'VE' },
    { id: 'Nazionale', code: 'NZ' }
  ];

  const WHEEL_IDS = WHEELS.map((wheel) => wheel.id);

  const PERIODS = [
    { id: 'oneYear', name: 'Ultimo anno', years: 1 },
    { id: 'twoYears', name: 'Ultimi 2 anni', years: 2 },
    { id: 'threeYears', name: 'Ultimi 3 anni', years: 3 },
    { id: 'fiveYears', name: 'Ultimi 5 anni', years: 5 },
    { id: 'tenYears', name: 'Ultimi 10 anni', years: 10 },
    { id: 'all', name: 'Tutta la storia', years: null }
  ];

  const STRATEGIES = [
    { id: 'frequency', name: 'Frequenza', explanation: 'Privilegia i numeri con la frequenza storica più alta nel periodo selezionato.' },
    { id: 'delay', name: 'Ritardo', explanation: 'Privilegia i numeri con il ritardo attuale più elevato rispetto alla loro media storica.' },
    { id: 'balanced', name: 'Bilanciata', explanation: 'Mescola numeri frequenti, ritardatari e di frequenza media rispettando i vincoli di equilibrio.' },
    { id: 'multiWheel', name: 'Multi-ruota', explanation: 'Considera i numeri che mostrano segnali statistici coerenti su più ruote contemporaneamente.' },
    { id: 'hot', name: 'Hot', explanation: 'Solo numeri con frequenza recente superiore alla media del periodo.' },
    { id: 'cold', name: 'Cold', explanation: 'Solo numeri con frequenza recente inferiore alla media del periodo.' },
    { id: 'trend', name: 'Trend', explanation: 'Privilegia i numeri la cui frequenza recente è in crescita rispetto alla frequenza storica.' },
    { id: 'statisticalRandom', name: 'Random statistica', explanation: 'Estrazione casuale vincolata: casuale, ma con somma, parità e distribuzione entro gli intervalli storici tipici.' },
    { id: 'conservative', name: 'Conservativa', explanation: 'Solo numeri con indice statistico elevato, poca varianza.' },
    { id: 'diversified', name: 'Diversificata', explanation: 'Massimizza la distanza dalle combinazioni già generate in questa sessione.' }
  ];

  const QUINTUPLE_MODES = [
    { id: 'conservative', name: 'Conservativa', subtitle: 'Numeri con indice statistico elevato', strategy: 'conservative' },
    { id: 'balanced', name: 'Bilanciata', subtitle: 'Mix di frequenti, ritardatari e medi', strategy: 'balanced' },
    { id: 'diversified', name: 'Diversificata', subtitle: 'Riduce la sovrapposizione con le combinazioni precedenti', strategy: 'diversified' },
    { id: 'statisticalRandom', name: 'Random statistica', subtitle: 'Casuale entro vincoli statistici', strategy: 'statisticalRandom' }
  ];

  const TEMPERATURES = [
    { id: 'hot', name: 'Hot', description: 'Frequenza recente elevata nel periodo selezionato.' },
    { id: 'cold', name: 'Cold', description: 'Frequenza recente bassa nel periodo selezionato.' },
    { id: 'overdue', name: 'Overdue', description: 'Ritardo attuale elevato rispetto al ritardo medio storico.' },
    { id: 'hotOverdue', name: 'Hot + Overdue', description: 'Frequenza recente elevata ma ritardo attuale sopra la media.' },
    { id: 'coldOverdue', name: 'Cold + Overdue', description: 'Frequenza recente bassa e ritardo attuale elevato.' },
    { id: 'hotRecent', name: 'Hot + Recent', description: 'Frequenza recente elevata e ultima uscita ravvicinata.' },
    { id: 'balanced', name: 'Balanced', description: 'Valori intermedi su tutti gli indicatori.' }
  ];

  const WEIGHT_PRESETS = {
    balanced: { frequency: 0.30, recency: 0.15, delay: 0.20, trend: 0.15, coOccurrence: 0.10, stability: 0.10 },
    frequencyFocused: { frequency: 0.60, recency: 0.10, delay: 0.05, trend: 0.10, coOccurrence: 0.10, stability: 0.05 },
    delayFocused: { frequency: 0.10, recency: 0.05, delay: 0.60, trend: 0.05, coOccurrence: 0.10, stability: 0.10 },
    trendFocused: { frequency: 0.15, recency: 0.25, delay: 0.05, trend: 0.45, coOccurrence: 0.05, stability: 0.05 },
    conservative: { frequency: 0.40, recency: 0.10, delay: 0.10, trend: 0.10, coOccurrence: 0.10, stability: 0.20 }
  };

  /** Pesi associati a ciascuna strategia di generazione. */
  function weightsForStrategy(strategyId) {
    switch (strategyId) {
      case 'frequency':
      case 'hot':
        return WEIGHT_PRESETS.frequencyFocused;
      case 'delay':
      case 'cold':
        return WEIGHT_PRESETS.delayFocused;
      case 'trend':
        return WEIGHT_PRESETS.trendFocused;
      case 'conservative':
        return WEIGHT_PRESETS.conservative;
      default:
        return WEIGHT_PRESETS.balanced;
    }
  }

  /** Riporta la somma dei pesi a 1, così l'indice resta fra 0 e 100. */
  function normalizeWeights(weights) {
    const keys = ['frequency', 'recency', 'delay', 'trend', 'coOccurrence', 'stability'];
    let total = 0;
    keys.forEach((key) => { total += Math.max(weights[key] || 0, 0); });
    if (total <= 0) return Object.assign({}, WEIGHT_PRESETS.balanced);
    const result = {};
    keys.forEach((key) => { result[key] = Math.max(weights[key] || 0, 0) / total; });
    return result;
  }

  const DISCLAIMER = {
    primary: 'Le estrazioni sono casuali. Le analisi statistiche degli estratti passati non modificano la probabilità matematica di vincita. Le combinazioni generate sono suggerimenti statistici e non previsioni certe.',
    score: 'Score statistico basato sui dati storici selezionati. Non rappresenta la probabilità reale che la combinazione venga estratta.',
    explainer: 'Questi dati descrivono il passato e non aumentano la probabilità matematica dell’estrazione futura.',
    delay: 'Il ritardo descrive quante estrazioni sono trascorse dall’ultima uscita. Un numero ritardatario non ha una probabilità matematica maggiore di uscire: ogni estrazione è indipendente dalle precedenti.',
    machineLearning: 'Il modulo di machine learning è sperimentale e serve a descrivere e classificare i pattern storici. Non è, e non può essere, uno strumento di previsione di un evento casuale.',
    noEdge: 'Nessun vantaggio predittivo dimostrato.',
    backtest: 'Il backtest è walk-forward: a ogni passo l’algoritmo vede soltanto le estrazioni precedenti alla data simulata. I risultati descrivono il comportamento storico della strategia e non garantiscono risultati futuri.',
    monteCarlo: 'La simulazione Monte Carlo genera estrazioni puramente casuali. Serve a verificare se i pattern osservati nei dati storici sono compatibili con il caso.'
  };

  /** Fascia qualitativa dello score. Solo descrittiva. */
  function scoreBand(score) {
    if (score >= 80) return { id: 'high', label: 'Indice statistico alto', emoji: '🟢' };
    if (score >= 50) return { id: 'medium', label: 'Indice statistico medio', emoji: '🟡' };
    return { id: 'low', label: 'Indice statistico basso', emoji: '🔴' };
  }

  /** Riconosce una ruota da una stringa proveniente da un file importato. */
  function parseWheel(raw) {
    if (!raw) return null;
    const normalized = String(raw).trim().normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    if (!normalized) return null;
    for (let i = 0; i < WHEELS.length; i += 1) {
      const wheel = WHEELS[i];
      if (wheel.id.toLowerCase() === normalized) return wheel.id;
      if (wheel.code.toLowerCase() === normalized) return wheel.id;
    }
    const aliases = { rn: 'Nazionale', naz: 'Nazionale', 'ruota nazionale': 'Nazionale', ro: 'Roma' };
    return aliases[normalized] || null;
  }

  function wheelCode(wheelId) {
    const wheel = WHEELS.find((item) => item.id === wheelId);
    return wheel ? wheel.code : (wheelId || '');
  }

  function periodById(id) {
    return PERIODS.find((period) => period.id === id) || PERIODS[3];
  }

  root.Lotto = root.Lotto || {};
  Object.assign(root.Lotto, {
    GAMES: GAMES,
    WHEELS: WHEELS,
    WHEEL_IDS: WHEEL_IDS,
    PERIODS: PERIODS,
    STRATEGIES: STRATEGIES,
    QUINTUPLE_MODES: QUINTUPLE_MODES,
    TEMPERATURES: TEMPERATURES,
    WEIGHT_PRESETS: WEIGHT_PRESETS,
    DISCLAIMER: DISCLAIMER,
    weightsForStrategy: weightsForStrategy,
    normalizeWeights: normalizeWeights,
    scoreBand: scoreBand,
    parseWheel: parseWheel,
    wheelCode: wheelCode,
    periodById: periodById
  });
})(typeof self !== 'undefined' ? self : this);
