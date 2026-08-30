/* Contesto di analisi: estrazioni filtrate, statistiche, indici e score.
   Costruito una sola volta e riusato da tutti i generatori, così che ambi,
   terni e cinquine siano coerenti fra loro. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  function buildContext(filter, allDraws, weights) {
    const game = Lotto.GAMES[filter.game];
    const draws = Lotto.applyFilter(filter, allDraws);
    const statistics = Lotto.computeStatistics(draws, filter.game);
    const occurrences = Lotto.buildOccurrenceIndex(draws, game.drawnCount);
    const scores = Lotto.scoreNumbers(statistics, weights);

    let sumMean;
    let sumStandardDeviation;
    if (statistics.sums.length === 0) {
      // Valori teorici per k numeri estratti senza reimmissione da 1…90.
      const k = game.drawnCount;
      sumMean = k * 45.5;
      sumStandardDeviation = Math.sqrt((k * (90 * 90 - 1) / 12) * ((90 - k) / 89));
    } else {
      let total = 0;
      for (let i = 0; i < statistics.sums.length; i += 1) total += statistics.sums[i];
      sumMean = total / statistics.sums.length;
      let variance = 0;
      for (let i = 0; i < statistics.sums.length; i += 1) {
        variance += Math.pow(statistics.sums[i] - sumMean, 2);
      }
      variance /= Math.max(statistics.sums.length - 1, 1);
      sumStandardDeviation = Math.max(Math.sqrt(variance), 1);
    }

    return {
      filter: filter,
      game: filter.game,
      gameInfo: game,
      draws: draws,
      statistics: statistics,
      occurrences: occurrences,
      scores: scores,
      weights: weights,
      drawCount: draws.length,
      isEmpty: draws.length === 0,
      sumMean: sumMean,
      sumStandardDeviation: sumStandardDeviation
    };
  }

  function scoreOf(context, number) {
    const entry = context.scores[number];
    return entry ? entry.score : 0;
  }

  function statsOf(context, number) {
    return context.statistics.numbers[number];
  }

  /** I `limit` numeri con indice statistico più alto. */
  function topNumbers(context, limit) {
    return Lotto.rankedNumbers(context.scores).slice(0, limit).map((item) => item.number);
  }

  /** Descrizione leggibile del filtro, usata nei report e nelle intestazioni. */
  function describeFilter(filter) {
    const parts = [Lotto.GAMES[filter.game].name];
    if (Lotto.GAMES[filter.game].usesWheels) {
      parts.push(!filter.wheel || filter.wheel === 'all' ? 'Tutte le ruote' : filter.wheel);
    }
    if (filter.calendarYear) {
      parts.push('anno ' + filter.calendarYear);
    } else {
      parts.push(Lotto.periodById(filter.period || 'all').name.toLowerCase());
    }
    return parts.join(' · ');
  }

  Object.assign(Lotto, {
    buildContext: buildContext,
    scoreOf: scoreOf,
    statsOf: statsOf,
    topNumbers: topNumbers,
    describeFilter: describeFilter
  });
})(typeof self !== 'undefined' ? self : this);
