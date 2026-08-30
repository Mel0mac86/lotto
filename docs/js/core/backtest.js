/* BACKTESTING walk-forward e protezione dal data leakage.

   A ogni passo il motore ricostruisce le statistiche usando SOLTANTO le estrazioni
   con data strettamente precedente a quella simulata (filter.cutoff). Non esiste
   alcun percorso che permetta ai dati futuri di entrare nel calcolo. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  /** Moltiplicatori teorici lordi per posta unitaria. */
  const PAYOUTS = {
    lotto: { 1: 11.232, 2: 250, 3: 4500, 4: 120000, 5: 6000000 },
    // Il SuperEnalotto è a totalizzatore: valori indicativi e configurabili.
    superenalotto: { 2: 5, 3: 30, 4: 300, 5: 30000, 6: 2000000 }
  };

  const STRATEGY_KINDS = [
    { id: 'pairs', name: 'Top ambi', size: 2, threshold: 2 },
    { id: 'triples', name: 'Top terni', size: 3, threshold: 3 },
    { id: 'quintuples', name: 'Cinquina AI', size: null, threshold: 2 },
    { id: 'randomBaseline', name: 'Baseline casuale', size: null, threshold: 2 }
  ];

  function kindById(id) {
    return STRATEGY_KINDS.find((kind) => kind.id === id) || STRATEGY_KINDS[0];
  }

  function playSize(kind, gameId) {
    return kind.size || Lotto.GAMES[gameId].drawnCount;
  }

  function payoutFor(table, matched, stake) {
    return (table[matched] || 0) * stake;
  }

  function emptySummary() {
    return { totalPlays: 0, totalCost: 0, totalWinnings: 0, hitDistribution: {}, winningPlays: 0 };
  }

  function finalizeSummary(summary) {
    summary.net = summary.totalWinnings - summary.totalCost;
    summary.roi = summary.totalCost > 0 ? (summary.net / summary.totalCost) * 100 : 0;
    summary.hitRate = summary.totalPlays > 0 ? summary.winningPlays / summary.totalPlays : 0;
    return summary;
  }

  function generatePlays(configuration, context, generator) {
    const kind = kindById(configuration.kind);
    switch (kind.id) {
      case 'pairs': {
        const pool = Lotto.topNumbers(context, configuration.candidatePoolSize || 40);
        return Lotto.topPairs(context, configuration.playsPerDraw, pool).map((pair) => pair.numbers);
      }
      case 'triples':
        return Lotto.topTriples(context, configuration.playsPerDraw, configuration.candidatePoolSize || 40)
          .map((triple) => triple.numbers);
      case 'quintuples':
        return Lotto.generateCombinations({
          context: context,
          mode: configuration.mode || 'balanced',
          count: configuration.playsPerDraw,
          seed: Number(generator.nextBig() % 1000000007n),
          candidateSamples: 1200
        }).map((combination) => combination.numbers);
      default: {
        const size = playSize(kind, configuration.game);
        const plays = [];
        for (let i = 0; i < configuration.playsPerDraw; i += 1) {
          plays.push(generator.drawNumbers(size, 90));
        }
        return plays;
      }
    }
  }

  /** Esegue il backtest. `onProgress` riceve valori 0…1. */
  function runBacktest(configuration, allDraws, onProgress) {
    const started = Date.now();
    const game = Lotto.GAMES[configuration.game];
    const payouts = configuration.payouts || PAYOUTS[configuration.game];
    const kind = kindById(configuration.kind);
    const minimumHistory = configuration.minimumHistory || 60;

    let gameDraws = allDraws.filter((draw) => draw.game === configuration.game);
    if (game.usesWheels && configuration.wheel && configuration.wheel !== 'all') {
      gameDraws = gameDraws.filter((draw) => draw.wheel === configuration.wheel);
    }
    gameDraws.sort((a, b) => a.date - b.date);

    const testDraws = gameDraws.filter((draw) => draw.date >= configuration.startDate
      && draw.date <= configuration.endDate);

    const steps = [];
    const strategy = emptySummary();
    const baseline = emptySummary();
    const generator = new Lotto.SeededRandom(configuration.seed || 7);
    const size = playSize(kind, configuration.game);

    for (let index = 0; index < testDraws.length; index += 1) {
      if (onProgress && index % 5 === 0) onProgress(index / Math.max(testDraws.length, 1));
      const target = testDraws[index];

      // ---- Barriera anti data-leakage --------------------------------
      // Vengono usate solo le estrazioni con data < target.date.
      const filter = {
        game: configuration.game,
        wheel: configuration.wheel || 'all',
        period: configuration.lookback || 'fiveYears',
        cutoff: target.date
      };
      const history = Lotto.applyFilter(filter, gameDraws);
      if (history.length < minimumHistory) continue;
      // ----------------------------------------------------------------

      const context = Lotto.buildContext(filter, gameDraws, configuration.weights || Lotto.WEIGHT_PRESETS.balanced);
      const plays = generatePlays(configuration, context, generator);
      if (!plays.length) continue;

      const drawn = new Set(target.numbers);
      const matches = [];
      let stepWinnings = 0;
      const stepCost = plays.length * configuration.stakePerPlay;

      plays.forEach((play) => {
        let matched = 0;
        play.forEach((number) => { if (drawn.has(number)) matched += 1; });
        matches.push(matched);
        strategy.totalPlays += 1;
        strategy.hitDistribution[matched] = (strategy.hitDistribution[matched] || 0) + 1;
        if (matched >= kind.threshold) strategy.winningPlays += 1;
        stepWinnings += payoutFor(payouts, matched, configuration.stakePerPlay);
      });
      strategy.totalCost += stepCost;
      strategy.totalWinnings += stepWinnings;

      // Baseline: stesse dimensioni e stesso numero di giocate, numeri casuali.
      plays.forEach(() => {
        const random = generator.drawNumbers(size, 90);
        let matched = 0;
        random.forEach((number) => { if (drawn.has(number)) matched += 1; });
        baseline.totalPlays += 1;
        baseline.hitDistribution[matched] = (baseline.hitDistribution[matched] || 0) + 1;
        if (matched >= kind.threshold) baseline.winningPlays += 1;
        baseline.totalWinnings += payoutFor(payouts, matched, configuration.stakePerPlay);
      });
      baseline.totalCost += stepCost;

      steps.push({
        date: target.date,
        wheel: target.wheel,
        drawnNumbers: target.numbers,
        plays: plays,
        matches: matches,
        bestMatch: matches.length ? Math.max.apply(null, matches) : 0,
        cost: stepCost,
        winnings: stepWinnings,
        net: stepWinnings - stepCost
      });
    }
    if (onProgress) onProgress(1);

    finalizeSummary(strategy);
    finalizeSummary(baseline);

    const significance = Lotto.twoProportionZTest(
      strategy.winningPlays, strategy.totalPlays,
      baseline.winningPlays, baseline.totalPlays,
      'Strategia contro baseline casuale');

    let verdict;
    if (steps.length === 0) {
      verdict = 'Dati insufficienti nel periodo selezionato per eseguire il backtest.';
    } else if (!significance.isSignificant) {
      verdict = Lotto.DISCLAIMER.noEdge
        + ' Nel periodo testato la strategia non ha prodotto una differenza statisticamente significativa rispetto a giocate casuali.';
    } else if (strategy.hitRate > baseline.hitRate) {
      verdict = 'Nel campione analizzato la strategia mostra una differenza statisticamente significativa rispetto alla baseline casuale. Il risultato riguarda esclusivamente il periodo testato e non dimostra capacità predittiva su estrazioni future.';
    } else {
      verdict = 'Nel campione analizzato la strategia ha ottenuto risultati significativamente peggiori della baseline casuale.';
    }

    return {
      configuration: configuration,
      steps: steps,
      strategy: strategy,
      baseline: baseline,
      significance: significance,
      drawsEvaluated: steps.length,
      verdict: verdict,
      elapsed: (Date.now() - started) / 1000
    };
  }

  Object.assign(Lotto, {
    PAYOUTS: PAYOUTS,
    STRATEGY_KINDS: STRATEGY_KINDS,
    backtestKindById: kindById,
    runBacktest: runBacktest
  });
})(typeof self !== 'undefined' ? self : this);
