/* SISTEMA DI VALIDAZIONE: nessun algoritmo può essere presentato come "migliore"
   prima di aver superato backtest, walk-forward su più finestre, confronto con
   baseline casuale, Monte Carlo e test statistici.

   Il verdetto è volutamente conservativo: dichiara un vantaggio solo se TUTTI
   i controlli lo confermano. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  function validateStrategy(configuration, allDraws, options, onProgress) {
    const settings = Object.assign({ folds: 4, includeML: true }, options || {});
    if (onProgress) onProgress(0.05);

    const backtest = Lotto.runBacktest(configuration, allDraws, (value) => {
      if (onProgress) onProgress(0.05 + value * 0.45);
    });

    // Walk-forward su finestre consecutive e non sovrapposte.
    const folds = [];
    const totalInterval = configuration.endDate - configuration.startDate;
    if (totalInterval > 0 && settings.folds > 1) {
      const foldInterval = totalInterval / settings.folds;
      for (let index = 0; index < settings.folds; index += 1) {
        const foldConfiguration = Object.assign({}, configuration, {
          startDate: configuration.startDate + foldInterval * index,
          endDate: configuration.startDate + foldInterval * (index + 1)
        });
        const result = Lotto.runBacktest(foldConfiguration, allDraws);
        if (result.strategy.totalPlays === 0) continue;
        folds.push({
          index: index,
          start: foldConfiguration.startDate,
          end: foldConfiguration.endDate,
          hitRate: result.strategy.hitRate,
          baselineHitRate: result.baseline.hitRate,
          difference: result.strategy.hitRate - result.baseline.hitRate,
          plays: result.strategy.totalPlays
        });
        if (onProgress) onProgress(0.5 + ((index + 1) / settings.folds) * 0.25);
      }
    }

    const filter = {
      game: configuration.game,
      wheel: configuration.wheel || 'all',
      period: configuration.lookback || 'fiveYears',
      cutoff: configuration.endDate
    };
    const context = Lotto.buildContext(filter, allDraws, configuration.weights || Lotto.WEIGHT_PRESETS.balanced);
    const monteCarloTests = Lotto.randomnessTests(context);
    if (onProgress) onProgress(0.85);

    let mlEvaluation = null;
    if (settings.includeML) {
      mlEvaluation = Lotto.evaluateModel('logisticRegression', context.draws, configuration.game);
    }
    if (onProgress) onProgress(1);

    const backtestPassed = backtest.significance.isSignificant
      && backtest.strategy.hitRate > backtest.baseline.hitRate;
    const positiveFolds = folds.filter((fold) => fold.difference > 0).length;
    const foldsPassed = folds.length > 0 && positiveFolds / folds.length >= 0.75;
    const mlPassed = (mlEvaluation ? mlEvaluation.auc : 0.5) > 0.55;
    const significantTests = monteCarloTests.filter((test) => test.isSignificant);

    const checks = [];
    checks.push({
      name: 'Backtest walk-forward',
      passed: backtestPassed,
      detail: backtest.significance.interpretation
    });
    if (folds.length) {
      checks.push({
        name: 'Validazione su ' + folds.length + ' finestre',
        passed: foldsPassed,
        detail: positiveFolds + ' finestre su ' + folds.length + ' superano la baseline casuale.'
      });
    }
    if (monteCarloTests.length) {
      checks.push({
        name: 'Confronto Monte Carlo',
        passed: significantTests.length > 0,
        detail: significantTests.length === 0
          ? 'I dati storici sono compatibili con la casualità su tutti i test eseguiti.'
          : 'Test con scostamento: ' + significantTests.map((test) => test.name).join(', ') + '.'
      });
    }
    if (mlEvaluation) {
      checks.push({
        name: 'Modello di machine learning',
        passed: mlPassed,
        detail: 'AUC ' + mlEvaluation.auc.toFixed(3).replace('.', ',') + ' (0,500 = nessuna capacità discriminante).'
      });
    }

    const edgeDemonstrated = backtest.drawsEvaluated > 0 && backtestPassed && foldsPassed && mlPassed;
    const verdict = backtest.drawsEvaluated === 0
      ? 'Validazione non eseguibile: dati storici insufficienti nel periodo selezionato.'
      : (edgeDemonstrated
        ? 'Il vantaggio osservato supera tutti i controlli su questo campione. Resta un risultato retrospettivo: su un processo casuale non è replicabile in modo sistematico.'
        : Lotto.DISCLAIMER.noEdge);

    return {
      strategyName: Lotto.backtestKindById(configuration.kind).name,
      backtest: backtest,
      folds: folds,
      monteCarloTests: monteCarloTests,
      mlEvaluation: mlEvaluation,
      checks: checks,
      isEdgeDemonstrated: edgeDemonstrated,
      verdict: verdict,
      generatedAt: Date.now()
    };
  }

  Object.assign(Lotto, { validateStrategy: validateStrategy });
})(typeof self !== 'undefined' ? self : this);
