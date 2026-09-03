/* Web Worker: esegue i calcoli pesanti fuori dal thread dell'interfaccia,
   così la schermata resta reattiva durante backtest, Monte Carlo e ML. */
'use strict';

importScripts(
  'core/random.js',
  'core/models.js',
  'core/cooccurrence.js',
  'core/statistics.js',
  'core/scoring.js',
  'core/context.js',
  'core/combinations.js',
  'core/generators.js',
  'core/stats-tests.js',
  'core/montecarlo.js',
  'core/multiwheel.js',
  'core/backtest.js',
  'core/ml.js',
  'core/patterns.js',
  'core/validation.js',
  'core/explainer.js'
);

/* Le estrazioni vengono trasferite una volta sola e tenute qui: rimandarle a
   ogni richiesta costerebbe una serializzazione da megabyte. */
let allDraws = [];

function contextFor(payload) {
  const weights = payload.weights || Lotto.WEIGHT_PRESETS.balanced;
  return Lotto.buildContext(payload.filter, allDraws, weights);
}

function progressReporter(id) {
  return function (value) {
    self.postMessage({ id: id, type: 'progress', value: value });
  };
}

const HANDLERS = {
  setDraws: function (payload) {
    allDraws = payload.draws.map((draw) =>
      Lotto.makeDraw(draw.date, draw.game, draw.wheel, draw.numbers, draw.jolly, draw.superstar));
    return { count: allDraws.length };
  },

  analyze: function (payload) {
    const context = contextFor(payload);
    return { summary: serializeContext(context) };
  },

  pairs: function (payload) {
    const context = contextFor(payload);
    return { pairs: Lotto.topPairs(context, payload.limit || 10), summary: serializeContext(context) };
  },

  triples: function (payload) {
    const context = contextFor(payload);
    return {
      triples: Lotto.topTriples(context, payload.limit || 10, payload.poolSize || 45),
      summary: serializeContext(context)
    };
  },

  quadruples: function (payload) {
    const context = contextFor(payload);
    return {
      quadruples: Lotto.topQuadruples(context, payload.limit || 10, payload.poolSize || 45),
      summary: serializeContext(context)
    };
  },

  ambetti: function (payload) {
    const context = contextFor(payload);
    return {
      ambetti: Lotto.topAmbetti(context, payload.limit || 10, payload.poolSize || 45),
      summary: serializeContext(context)
    };
  },

  combinations: function (payload) {
    const context = contextFor(payload);
    const combinations = Lotto.generateCombinations({
      context: context,
      mode: payload.mode,
      strategy: payload.strategy,
      count: payload.count || 5,
      seed: payload.seed || 0,
      avoid: payload.avoid || [],
      candidateSamples: payload.candidateSamples || 4000
    });
    return {
      combinations: combinations.map((item) => ({
        numbers: item.numbers,
        score: item.score,
        components: item.components,
        reasons: item.reasons,
        explanation: Lotto.explain(item, context, payload.strategy || payload.mode)
      })),
      summary: serializeContext(context)
    };
  },

  multiWheel: function (payload) {
    const weights = payload.weights || Lotto.WEIGHT_PRESETS.balanced;
    const contexts = Lotto.buildWheelContexts(payload.filter, allDraws, weights);
    const combination = Lotto.multiWheelCombination(contexts, 5, payload.seed || 0);
    return {
      numbers: Lotto.multiWheelNumbers(contexts, 65, 30),
      pairs: Lotto.multiWheelPairs(contexts, 10),
      triples: Lotto.multiWheelTriples(contexts, 10),
      combination: combination,
      wheelCount: Object.keys(contexts).length
    };
  },

  monteCarlo: function (payload, id) {
    const context = contextFor(payload);
    const result = Lotto.runMonteCarlo(context, payload.iterations || 100000,
      payload.seed || 20260101, progressReporter(id));
    return { result: result, summary: serializeContext(context) };
  },

  backtest: function (payload, id) {
    return { result: Lotto.runBacktest(payload.configuration, allDraws, progressReporter(id)) };
  },

  validate: function (payload, id) {
    return { report: Lotto.validateStrategy(payload.configuration, allDraws, {}, progressReporter(id)) };
  },

  patterns: function (payload) {
    const context = contextFor(payload);
    return { patterns: Lotto.analyzePatterns(context), summary: serializeContext(context) };
  },

  ml: function (payload, id) {
    const context = contextFor(payload);
    const model = payload.model;
    if (model === 'clustering') return { clusters: Lotto.clusterNumbers(context, 4) };
    if (model === 'anomalyDetection') return { anomalies: Lotto.anomalies(context, 12) };
    if (model === 'bayesian') {
      const posteriors = Lotto.bayesianPosteriors(context);
      return { posteriors: posteriors, bayesianSummary: Lotto.bayesianSummary(posteriors) };
    }
    return {
      evaluation: Lotto.evaluateModel(model, context.draws, payload.filter.game, progressReporter(id))
    };
  },

  numberDetail: function (payload) {
    const context = contextFor(payload);
    const matrix = Lotto.buildCoOccurrence(context.draws, context.gameInfo.drawnCount);
    return {
      statistics: context.statistics.numbers[payload.number],
      score: context.scores[payload.number],
      partners: Lotto.topPartners(matrix, payload.number, 8),
      explanation: Lotto.explainNumber(payload.number, context),
      byYear: context.statistics.byYear,
      byMonth: context.statistics.byMonth,
      summary: serializeContext(context)
    };
  }
};

/* Il contesto completo pesa troppo per essere trasferito: si invia solo ciò
   che l'interfaccia deve mostrare. */
function serializeContext(context) {
  const numbers = [];
  for (let n = 1; n <= 90; n += 1) {
    const stats = context.statistics.numbers[n];
    const entry = context.scores[n];
    numbers.push({
      number: n,
      occurrences: stats.occurrences,
      frequency: stats.frequency,
      expectedFrequency: stats.expectedFrequency,
      frequencyRatio: stats.frequencyRatio,
      frequencyPercentile: stats.frequencyPercentile,
      currentDelay: stats.currentDelay,
      averageDelay: stats.averageDelay,
      maxDelay: stats.maxDelay,
      delayRatio: stats.delayRatio,
      lastSeen: stats.lastSeen,
      trendRatio: stats.trendRatio,
      recentFrequency: stats.recentFrequency,
      volatility: stats.volatility,
      score: entry ? entry.score : 0,
      components: entry ? entry.components : null,
      tags: Lotto.temperatureTags(stats)
    });
  }
  return {
    filter: context.filter,
    description: Lotto.describeFilter(context.filter),
    drawCount: context.drawCount,
    firstDate: context.statistics.firstDate,
    lastDate: context.statistics.lastDate,
    sumMean: context.sumMean,
    numbers: numbers,
    evenDistribution: context.statistics.evenDistribution,
    lowDistribution: context.statistics.lowDistribution,
    decadeDistribution: context.statistics.decadeDistribution,
    unitDistribution: context.statistics.unitDistribution,
    drawsWithConsecutives: context.statistics.drawsWithConsecutives,
    byYear: context.statistics.byYear,
    byWheel: context.statistics.byWheel,
    sums: context.statistics.sums
  };
}

self.onmessage = function (event) {
  const message = event.data || {};
  const handler = HANDLERS[message.type];
  if (!handler) {
    self.postMessage({ id: message.id, type: 'error', error: 'Operazione sconosciuta: ' + message.type });
    return;
  }
  try {
    const result = handler(message.payload || {}, message.id);
    self.postMessage({ id: message.id, type: 'result', result: result });
  } catch (error) {
    self.postMessage({ id: message.id, type: 'error', error: error && error.message ? error.message : String(error) });
  }
};
