/* STATISTICAL NUMBER SCORE: indice statistico 0–100 per ciascun numero.
   Ogni criterio è normalizzato in percentile rispetto agli altri 89 numeri,
   poi combinato secondo i pesi configurati.

   È un indice DESCRITTIVO del passato, non una probabilità di uscita. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  function clamp(value, lower, upper) {
    const min = lower === undefined ? 0 : lower;
    const max = upper === undefined ? 100 : upper;
    if (!isFinite(value)) return min;
    return Math.min(Math.max(value, min), max);
  }

  /** Percentile 0–100 di ogni valore rispetto agli altri, con pari merito mediati. */
  function percentileRanks(values) {
    if (values.length <= 1) return values.map(() => 50);
    const sorted = values.map((value, index) => ({ value: value, index: index }));
    sorted.sort((a, b) => a.value - b.value);
    const ranks = new Array(values.length).fill(0);
    const denominator = values.length - 1;

    let position = 0;
    while (position < sorted.length) {
      let end = position;
      while (end + 1 < sorted.length && sorted[end + 1].value === sorted[position].value) end += 1;
      const averageRank = (position + end) / 2;
      const percentile = (averageRank / denominator) * 100;
      for (let i = position; i <= end; i += 1) ranks[sorted[i].index] = percentile;
      position = end + 1;
    }
    return ranks;
  }

  /** Mappa il rapporto frequenza recente / frequenza storica su 0–100.
      Un rapporto di 1,0 (nessun cambiamento) restituisce 50. */
  function trendScore(ratio) {
    if (!isFinite(ratio)) return 50;
    const logRatio = Math.log(Math.max(ratio, 0.01));
    const sigmoid = 1 / (1 + Math.exp(-logRatio * 4.0));
    return clamp(sigmoid * 100);
  }

  /** Calcola l'indice statistico di tutti i numeri. */
  function scoreNumbers(statistics, weights) {
    const normalized = Lotto.normalizeWeights(weights);
    const items = [];
    for (let number = 1; number <= 90; number += 1) items.push(statistics.numbers[number]);

    const frequencyRank = percentileRanks(items.map((item) => item.occurrences));
    const coOccurrenceRank = percentileRanks(items.map((item) => item.coOccurrenceStrength));
    const delayRank = percentileRanks(items.map((item) => item.currentDelay));
    const volatilityRank = percentileRanks(items.map((item) => item.volatility));

    const scores = {};
    for (let i = 0; i < items.length; i += 1) {
      const item = items[i];
      const components = {
        frequency: frequencyRank[i],
        // Recenza: alto = uscito da poco. È l'inverso del ritardo.
        recency: 100 - delayRank[i],
        delay: delayRank[i],
        trend: trendScore(item.trendRatio),
        coOccurrence: coOccurrenceRank[i],
        // Stabilità: alto = frequenza costante nel tempo (bassa volatilità).
        stability: 100 - volatilityRank[i],
        balance: 0
      };
      const total = components.frequency * normalized.frequency
        + components.recency * normalized.recency
        + components.delay * normalized.delay
        + components.trend * normalized.trend
        + components.coOccurrence * normalized.coOccurrence
        + components.stability * normalized.stability;

      scores[item.number] = {
        number: item.number,
        score: clamp(total),
        components: components,
        statistics: item
      };
    }
    return scores;
  }

  /** Numeri ordinati per indice statistico decrescente. */
  function rankedNumbers(scores) {
    const list = Object.keys(scores).map((key) => scores[key]);
    list.sort((a, b) => (b.score - a.score) || (a.number - b.number));
    return list;
  }

  const COMPONENT_LABELS = [
    ['frequency', 'Frequenza'],
    ['recency', 'Recenza'],
    ['delay', 'Ritardo'],
    ['trend', 'Trend'],
    ['coOccurrence', 'Co-occorrenza'],
    ['stability', 'Stabilità'],
    ['balance', 'Equilibrio']
  ];

  function labelledComponents(components) {
    return COMPONENT_LABELS.map((pair) => ({
      key: pair[0],
      label: pair[1],
      value: components[pair[0]] || 0
    }));
  }

  Object.assign(Lotto, {
    clamp: clamp,
    percentileRanks: percentileRanks,
    trendScore: trendScore,
    scoreNumbers: scoreNumbers,
    rankedNumbers: rankedNumbers,
    labelledComponents: labelledComponents
  });
})(typeof self !== 'undefined' ? self : this);
