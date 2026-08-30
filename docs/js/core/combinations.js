/* Valutazione di una combinazione: indice statistico complessivo, equilibrio
   rispetto alle distribuzioni storiche e spiegazioni in italiano. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  const COMBINATION_WEIGHTS = {
    default: { numberScore: 0.55, coOccurrence: 0.25, balance: 0.20 },
    // Per gli ambi la co-occorrenza pesa di più: è il criterio caratterizzante.
    pair: { numberScore: 0.45, coOccurrence: 0.45, balance: 0.10 },
    triple: { numberScore: 0.45, coOccurrence: 0.35, balance: 0.20 }
  };

  /** Media dei lift di tutte le coppie interne, mappata su 0–100. */
  function coOccurrenceScore(numbers, context) {
    if (numbers.length < 2) return 50;
    let total = 0;
    let count = 0;
    for (let i = 0; i < numbers.length - 1; i += 1) {
      for (let j = i + 1; j < numbers.length; j += 1) {
        total += Lotto.indexPairLift(context.occurrences, numbers[i], numbers[j]);
        count += 1;
      }
    }
    if (count === 0) return 50;
    // lift 1,0 (perfettamente in media) -> 50 punti.
    return Lotto.clamp(50 * (total / count));
  }

  /** Quanto la combinazione è "tipica" rispetto alle distribuzioni storiche. */
  function balanceScore(numbers, context) {
    const size = numbers.length;
    if (size < 2) return 50;

    let sum = 0;
    let even = 0;
    let low = 0;
    const decades = {};
    for (let i = 0; i < size; i += 1) {
      const number = numbers[i];
      sum += number;
      if (number % 2 === 0) even += 1;
      if (number <= 45) low += 1;
      decades[Math.min(Math.floor((number - 1) / 10), 8)] = true;
    }

    const drawnCount = context.gameInfo.drawnCount;
    const expectedSum = (context.sumMean / drawnCount) * size;
    const expectedSigma = (context.sumStandardDeviation / Math.sqrt(drawnCount)) * Math.sqrt(size);
    const sumZ = expectedSigma > 0 ? Math.abs(sum - expectedSum) / expectedSigma : 0;
    const sumScore = 100 * Math.exp(-(sumZ * sumZ) / 2);

    const half = size / 2;
    const parityScore = 100 * (1 - Math.min(Math.abs(even - half) / half, 1));
    const rangeScore = 100 * (1 - Math.min(Math.abs(low - half) / half, 1));
    const decadeScore = 100 * (Object.keys(decades).length / Math.min(size, 9));

    const sorted = numbers.slice().sort((a, b) => a - b);
    const consecutive = Lotto.consecutivePairs(sorted);
    // Una coppia consecutiva è normale, tre o più sono un pattern raro.
    const consecutivePenalty = Math.max(consecutive - 1, 0) * 15;

    const raw = sumScore * 0.30 + parityScore * 0.20 + rangeScore * 0.20 + decadeScore * 0.30;
    return Lotto.clamp(raw - consecutivePenalty);
  }

  /** Percorso veloce: indice e componenti senza generare le spiegazioni. */
  function rawScore(numbers, context, weightsKey) {
    const weights = COMBINATION_WEIGHTS[weightsKey || 'default'];
    if (!numbers.length) return { score: 0, components: emptyComponents() };

    const components = emptyComponents();
    let scoreSum = 0;
    let counted = 0;
    for (let i = 0; i < numbers.length; i += 1) {
      const entry = context.scores[numbers[i]];
      if (!entry) continue;
      scoreSum += entry.score;
      components.frequency += entry.components.frequency;
      components.recency += entry.components.recency;
      components.delay += entry.components.delay;
      components.trend += entry.components.trend;
      components.stability += entry.components.stability;
      counted += 1;
    }
    if (counted === 0) return { score: 0, components: components };

    components.frequency /= counted;
    components.recency /= counted;
    components.delay /= counted;
    components.trend /= counted;
    components.stability /= counted;
    components.coOccurrence = coOccurrenceScore(numbers, context);
    components.balance = balanceScore(numbers, context);

    const total = (scoreSum / counted) * weights.numberScore
      + components.coOccurrence * weights.coOccurrence
      + components.balance * weights.balance;

    return { score: Lotto.clamp(total), components: components };
  }

  function emptyComponents() {
    return { frequency: 0, recency: 0, delay: 0, trend: 0, coOccurrence: 0, stability: 0, balance: 0 };
  }

  /** Valutazione completa, spiegazioni incluse. */
  function evaluateCombination(numbers, context, weightsKey) {
    const sorted = numbers.slice().sort((a, b) => a - b);
    const result = rawScore(sorted, context, weightsKey);
    return {
      numbers: sorted,
      score: result.score,
      components: result.components,
      reasons: explainCombination(sorted, context, result.components)
    };
  }

  function pad(number) { return number < 10 ? '0' + number : String(number); }
  function fmt(value, digits) {
    return Number(value).toFixed(digits === undefined ? 1 : digits).replace('.', ',');
  }

  function explainCombination(numbers, context, components) {
    const reasons = [];
    const stats = numbers.map((number) => Lotto.statsOf(context, number));

    let mostFrequent = null;
    let mostOverdue = null;
    let hottest = null;
    stats.forEach((item) => {
      if (!mostFrequent || item.occurrences > mostFrequent.occurrences) mostFrequent = item;
      if (!mostOverdue || item.currentDelay > mostOverdue.currentDelay) mostOverdue = item;
      if (!hottest || item.trendRatio > hottest.trendRatio) hottest = item;
    });

    if (mostFrequent && mostFrequent.occurrences > 0) {
      reasons.push('Il ' + pad(mostFrequent.number) + ' è il numero più frequente della combinazione: '
        + mostFrequent.occurrences + ' uscite su ' + context.drawCount + ' estrazioni ('
        + fmt(mostFrequent.frequency * 100) + '% contro un atteso del '
        + fmt(mostFrequent.expectedFrequency * 100) + '%).');
    }
    if (mostOverdue && mostOverdue.currentDelay > 0) {
      reasons.push('Il ' + pad(mostOverdue.number) + ' manca da ' + mostOverdue.currentDelay
        + ' estrazioni, con un ritardo medio storico di ' + fmt(mostOverdue.averageDelay)
        + ' e un massimo di ' + mostOverdue.maxDelay + '.');
    }
    if (hottest && hottest.trendRatio > 1.05) {
      reasons.push('Il ' + pad(hottest.number) + ' mostra una frequenza recente superiore del '
        + fmt((hottest.trendRatio - 1) * 100, 0) + '% rispetto alla sua frequenza nel periodo.');
    }

    if (numbers.length >= 2) {
      let best = null;
      for (let i = 0; i < numbers.length - 1; i += 1) {
        for (let j = i + 1; j < numbers.length; j += 1) {
          const lift = Lotto.indexPairLift(context.occurrences, numbers[i], numbers[j]);
          if (!best || lift > best.lift) {
            best = {
              a: numbers[i],
              b: numbers[j],
              lift: lift,
              count: Lotto.indexPairCount(context.occurrences, numbers[i], numbers[j])
            };
          }
        }
      }
      if (best && best.count > 0) {
        if (best.lift >= 1.15) {
          reasons.push('La coppia ' + pad(best.a) + '–' + pad(best.b) + ' è uscita insieme '
            + best.count + ' volte, il ' + fmt((best.lift - 1) * 100, 0)
            + '% in più di quanto atteso dal caso.');
        } else {
          reasons.push('La coppia più ricorrente è ' + pad(best.a) + '–' + pad(best.b) + ' con '
            + best.count + ' uscite congiunte (in linea con l’atteso).');
        }
      }
    }

    let sum = 0;
    let even = 0;
    let low = 0;
    numbers.forEach((number) => {
      sum += number;
      if (number % 2 === 0) even += 1;
      if (number <= 45) low += 1;
    });
    reasons.push('Distribuzione: ' + even + ' pari / ' + (numbers.length - even) + ' dispari, '
      + low + ' nella fascia 1–45 e ' + (numbers.length - low) + ' nella 46–90, somma ' + sum
      + ' (media storica ' + fmt((context.sumMean / context.gameInfo.drawnCount) * numbers.length, 0) + ').');

    if (components.balance >= 70) {
      reasons.push('L’equilibrio complessivo della combinazione è in linea con le distribuzioni storiche osservate.');
    } else if (components.balance < 40) {
      reasons.push('La combinazione è distribuita in modo atipico rispetto allo storico: somma o parità lontane dai valori più frequenti.');
    }

    reasons.push(Lotto.DISCLAIMER.explainer);
    return reasons;
  }

  Object.assign(Lotto, {
    COMBINATION_WEIGHTS: COMBINATION_WEIGHTS,
    coOccurrenceScore: coOccurrenceScore,
    balanceScore: balanceScore,
    rawScore: rawScore,
    evaluateCombination: evaluateCombination,
    explainCombination: explainCombination,
    pad: pad,
    fmt: fmt
  });
})(typeof self !== 'undefined' ? self : this);
