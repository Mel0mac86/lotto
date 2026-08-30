/* Generatori: ambi (tutte le 4.005 coppie), terni e cinquine/sestine.
   Porting di PairGenerator, TripleGenerator e QuintupleGenerator. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const pad = Lotto.pad;
  const fmt = Lotto.fmt;

  // ---------------------------------------------------------------- Ambi

  /** GENERA AMBO: valuta tutte le coppie possibili fra 1 e 90. */
  function topPairs(context, limit, pool) {
    if (context.isEmpty) return [];
    const max = 10;
    const results = [];

    // Conteggio delle coppie nella parte recente del periodo.
    const recentWindow = Math.max(Math.min(context.drawCount, 20), Math.floor(context.drawCount / 4));
    const recentDraws = context.draws.slice(context.drawCount - recentWindow);
    const recentCounts = new Int32Array(Lotto.PAIR_COUNT);
    recentDraws.forEach((draw) => {
      const numbers = draw.numbers;
      for (let i = 0; i < numbers.length - 1; i += 1) {
        for (let j = i + 1; j < numbers.length; j += 1) {
          recentCounts[Lotto.pairIndex(numbers[i], numbers[j])] += 1;
        }
      }
    });

    const allowed = pool ? new Set(pool) : null;
    const expected = context.occurrences.expectedPair;

    for (let a = 1; a <= 89; a += 1) {
      if (allowed && !allowed.has(a)) continue;
      for (let b = a + 1; b <= 90; b += 1) {
        if (allowed && !allowed.has(b)) continue;
        const evaluation = Lotto.rawScore([a, b], context, 'pair');
        results.push({
          first: a,
          second: b,
          numbers: [a, b],
          score: evaluation.score,
          components: evaluation.components,
          jointCount: Lotto.indexPairCount(context.occurrences, a, b),
          expectedCount: expected,
          delay: Lotto.indexPairDelay(context.occurrences, a, b),
          recentCount: recentCounts[Lotto.pairIndex(a, b)]
        });
      }
    }

    results.sort((x, y) => (y.score - x.score) || (y.jointCount - x.jointCount));
    const top = results.slice(0, limit || max);
    top.forEach((pair) => {
      pair.lift = pair.expectedCount > 0 ? pair.jointCount / pair.expectedCount : 0;
      pair.reasons = pairReasons(pair, context);
    });
    return top;
  }

  function pairReasons(pair, context) {
    const lines = [];
    const first = Lotto.statsOf(context, pair.first);
    const second = Lotto.statsOf(context, pair.second);

    lines.push('Uscite congiunte: ' + pair.jointCount + ' su ' + context.drawCount
      + ' estrazioni (attese dal caso: ' + fmt(pair.expectedCount) + ').');
    if (pair.lift > 1.05) {
      lines.push('Ricorrenza superiore all’atteso del ' + fmt((pair.lift - 1) * 100, 0) + '%.');
    } else if (pair.lift < 0.95 && pair.expectedCount > 0) {
      lines.push('Ricorrenza inferiore all’atteso del ' + fmt((1 - pair.lift) * 100, 0) + '%.');
    } else {
      lines.push('Ricorrenza congiunta sostanzialmente in linea con l’atteso casuale.');
    }
    lines.push('Ritardo dell’ambo: ' + pair.delay + ' estrazioni dall’ultima uscita congiunta.');
    lines.push('Frequenze individuali: ' + pad(first.number) + ' con ' + first.occurrences
      + ' uscite (ritardo ' + first.currentDelay + '), ' + pad(second.number) + ' con '
      + second.occurrences + ' uscite (ritardo ' + second.currentDelay + ').');
    if (pair.recentCount > 0) {
      lines.push('Nell’ultima parte del periodo la coppia è uscita ' + pair.recentCount + ' volte.');
    }
    lines.push(Lotto.DISCLAIMER.explainer);
    return lines;
  }

  // --------------------------------------------------------------- Terni

  /**
   * GENERA TERNO. Con `poolSize` pari a 90 enumera tutte le 117.480 terne,
   * altrimenti si limita ai numeri con indice statistico più alto.
   */
  function topTriples(context, limit, poolSize) {
    if (context.isEmpty) return [];
    const size = poolSize || 45;
    let pool;
    if (size >= 90) {
      pool = [];
      for (let n = 1; n <= 90; n += 1) pool.push(n);
    } else {
      pool = Lotto.topNumbers(context, Math.max(size, (limit || 10) + 5)).sort((a, b) => a - b);
    }
    if (pool.length < 3) return [];

    const expected = context.occurrences.expectedTriple;
    const keep = limit || 10;
    const best = [];

    for (let i = 0; i < pool.length - 2; i += 1) {
      for (let j = i + 1; j < pool.length - 1; j += 1) {
        for (let k = j + 1; k < pool.length; k += 1) {
          const numbers = [pool[i], pool[j], pool[k]];
          const evaluation = Lotto.rawScore(numbers, context, 'triple');
          if (best.length >= keep && evaluation.score <= best[best.length - 1].score) continue;
          const pairCounts = [
            Lotto.indexPairCount(context.occurrences, numbers[0], numbers[1]),
            Lotto.indexPairCount(context.occurrences, numbers[0], numbers[2]),
            Lotto.indexPairCount(context.occurrences, numbers[1], numbers[2])
          ];
          const entry = {
            numbers: numbers,
            score: evaluation.score,
            components: evaluation.components,
            jointCount: Lotto.indexTripleCount(context.occurrences, numbers[0], numbers[1], numbers[2]),
            expectedCount: expected,
            delay: Lotto.indexTripleDelay(context.occurrences, numbers[0], numbers[1], numbers[2]),
            sum: numbers[0] + numbers[1] + numbers[2],
            averagePairCount: (pairCounts[0] + pairCounts[1] + pairCounts[2]) / 3
          };
          insertSorted(best, entry, keep);
        }
      }
    }

    best.forEach((triple) => {
      triple.lift = triple.expectedCount > 0 ? triple.jointCount / triple.expectedCount : 0;
      triple.evenCount = triple.numbers.filter((n) => n % 2 === 0).length;
      triple.lowCount = triple.numbers.filter((n) => n <= 45).length;
      triple.averageGap = (triple.numbers[2] - triple.numbers[0]) / 2;
      triple.reasons = tripleReasons(triple, context);
    });
    return best;
  }

  /** Inserimento ordinato in un buffer dei migliori K: evita di ordinare 117.480 risultati. */
  function insertSorted(buffer, entry, capacity) {
    let position = buffer.length;
    while (position > 0 && buffer[position - 1].score < entry.score) position -= 1;
    buffer.splice(position, 0, entry);
    if (buffer.length > capacity) buffer.length = capacity;
  }

  function tripleReasons(triple, context) {
    const lines = [];
    const stats = triple.numbers.map((number) => Lotto.statsOf(context, number));
    lines.push('Frequenze individuali nel periodo: '
      + stats.map((item) => pad(item.number) + ' (' + item.occurrences + ' uscite)').join(', ') + '.');
    lines.push('Uscite congiunte delle coppie interne: ' + fmt(triple.averagePairCount) + ' in media.');
    if (triple.jointCount > 0) {
      lines.push('La terna completa è uscita ' + triple.jointCount + ' volte (attese dal caso: '
        + fmt(triple.expectedCount, 2) + '); ritardo attuale ' + triple.delay + ' estrazioni.');
    } else {
      lines.push('La terna completa non è mai uscita nel periodo analizzato (attese dal caso: '
        + fmt(triple.expectedCount, 2) + ' uscite).');
    }
    lines.push('Distribuzione: ' + triple.evenCount + ' pari / ' + (3 - triple.evenCount)
      + ' dispari, ' + triple.lowCount + ' in 1–45, somma ' + triple.sum
      + ', distanza media ' + fmt(triple.averageGap) + '.');
    let overdue = stats[0];
    stats.forEach((item) => { if (item.currentDelay > overdue.currentDelay) overdue = item; });
    lines.push('Ritardo più elevato del terno: ' + pad(overdue.number) + ' con '
      + overdue.currentDelay + ' estrazioni (massimo storico ' + overdue.maxDelay + ').');
    lines.push(Lotto.DISCLAIMER.explainer);
    return lines;
  }

  // ------------------------------------------------------------ Cinquine

  /** Vincoli statistici derivati dalle distribuzioni storiche osservate. */
  function derivedConstraints(context, size) {
    const scale = size / Math.max(context.gameInfo.drawnCount, 1);
    const mean = context.sumMean * scale;
    const sigma = context.sumStandardDeviation * Math.sqrt(scale);
    const half = size / 2;
    return {
      minSum: Math.max(Math.floor(mean - 1.5 * sigma), size),
      maxSum: Math.min(Math.ceil(mean + 1.5 * sigma), size * 90),
      minEven: Math.max(Math.floor(half - 1.5), 0),
      maxEven: Math.min(Math.ceil(half + 1.5), size),
      minLow: Math.max(Math.floor(half - 1.5), 0),
      maxLow: Math.min(Math.ceil(half + 1.5), size),
      minDistinctDecades: Math.max(size - 1, 2),
      maxConsecutivePairs: 1
    };
  }

  function relaxConstraints(constraints) {
    const span = constraints.maxSum - constraints.minSum;
    return {
      minSum: Math.max(constraints.minSum - Math.floor(span / 4), 1),
      maxSum: constraints.maxSum + Math.floor(span / 4),
      minEven: Math.max(constraints.minEven - 1, 0),
      maxEven: constraints.maxEven + 1,
      minLow: Math.max(constraints.minLow - 1, 0),
      maxLow: constraints.maxLow + 1,
      minDistinctDecades: Math.max(constraints.minDistinctDecades - 1, 1),
      maxConsecutivePairs: constraints.maxConsecutivePairs + 1
    };
  }

  function satisfiesConstraints(numbers, constraints) {
    let sum = 0;
    let even = 0;
    let low = 0;
    const decades = {};
    for (let i = 0; i < numbers.length; i += 1) {
      const number = numbers[i];
      sum += number;
      if (number % 2 === 0) even += 1;
      if (number <= 45) low += 1;
      decades[Math.min(Math.floor((number - 1) / 10), 8)] = true;
    }
    if (sum < constraints.minSum || sum > constraints.maxSum) return false;
    if (even < constraints.minEven || even > constraints.maxEven) return false;
    if (low < constraints.minLow || low > constraints.maxLow) return false;
    if (Object.keys(decades).length < Math.min(constraints.minDistinctDecades, numbers.length)) return false;
    return Lotto.consecutivePairs(numbers.slice().sort((a, b) => a - b)) <= constraints.maxConsecutivePairs;
  }

  /** Pesi di campionamento per la strategia scelta. */
  function samplingWeights(context, strategyId) {
    const weights = [];
    for (let number = 1; number <= 90; number += 1) {
      const stats = Lotto.statsOf(context, number);
      const score = Lotto.scoreOf(context, number);
      let base;
      switch (strategyId) {
        case 'frequency': base = stats.occurrences + 1; break;
        case 'delay': base = stats.currentDelay + 1; break;
        case 'hot': base = Lotto.isHot(stats) ? score + 20 : Math.max(score - 30, 1); break;
        case 'cold': base = Lotto.isCold(stats) ? score + 20 : Math.max(score - 30, 1); break;
        case 'trend': base = Lotto.trendScore(stats.trendRatio) + 1; break;
        case 'statisticalRandom': base = 1; break;
        case 'conservative': base = Math.pow(Math.max(score, 1), 2) / 50; break;
        default: base = Math.max(score, 1);
      }
      weights.push(Math.max(base, 0.1));
    }
    return weights;
  }

  function overlapWith(numbers, sets) {
    if (!sets.length) return 0;
    let maximum = 0;
    for (let s = 0; s < sets.length; s += 1) {
      let shared = 0;
      for (let i = 0; i < numbers.length; i += 1) if (sets[s].has(numbers[i])) shared += 1;
      if (shared > maximum) maximum = shared;
    }
    return maximum;
  }

  /**
   * CINQUINA AI. Le C(90,5) = 43.949.268 combinazioni non sono enumerabili:
   * si usa un campionamento pesato dagli indici statistici, filtrato dai vincoli
   * storici e affinato da una ricerca locale.
   */
  function generateCombinations(options) {
    const context = options.context;
    if (context.isEmpty) return [];

    const size = options.size || context.gameInfo.drawnCount;
    const modeId = options.mode || 'balanced';
    const mode = Lotto.QUINTUPLE_MODES.find((item) => item.id === modeId) || Lotto.QUINTUPLE_MODES[1];
    const strategyId = options.strategy || mode.strategy;
    const strategy = Lotto.STRATEGIES.find((item) => item.id === strategyId);
    const count = options.count || 5;
    const samples = options.candidateSamples || 4000;
    const generator = new Lotto.SeededRandom(options.seed || Date.now());

    const weights = samplingWeights(context, strategyId);
    let constraints = derivedConstraints(context, size);
    const selected = [];
    const avoidSets = (options.avoid || []).map((numbers) => new Set(numbers));
    let emptyRounds = 0;

    while (selected.length < count) {
      let best = null;
      for (let attempt = 0; attempt < samples; attempt += 1) {
        const indices = generator.weightedSample(weights, size);
        if (indices.length !== size) continue;
        const numbers = indices.map((index) => index + 1).sort((a, b) => a - b);
        if (!satisfiesConstraints(numbers, constraints)) continue;
        const evaluation = Lotto.rawScore(numbers, context, 'default');
        const penalty = overlapWith(numbers, avoidSets) * (modeId === 'diversified' ? 12 : 4);
        const score = Lotto.clamp(evaluation.score - penalty);
        if (!best || score > best.score) {
          best = { numbers: numbers, score: score, components: evaluation.components };
        }
      }

      if (!best) {
        emptyRounds += 1;
        if (emptyRounds > 3) break;
        constraints = relaxConstraints(constraints);
        continue;
      }
      emptyRounds = 0;

      const refined = localSearch(best, context, constraints, avoidSets, modeId === 'diversified');
      if (selected.some((item) => item.numbers.join('-') === refined.numbers.join('-'))) {
        constraints = relaxConstraints(constraints);
        continue;
      }
      refined.reasons = Lotto.explainCombination(refined.numbers, context, refined.components);
      refined.reasons.unshift('Modalità ' + mode.name + ': ' + (strategy ? strategy.explanation : ''));
      selected.push(refined);
      avoidSets.push(new Set(refined.numbers));
    }

    selected.sort((a, b) => b.score - a.score);
    return selected;
  }

  /** Prova a sostituire un numero alla volta per migliorare l'indice statistico. */
  function localSearch(combination, context, constraints, avoidSets, diversify) {
    let current = combination;
    const pool = Lotto.topNumbers(context, 45);

    for (let iteration = 0; iteration < 3; iteration += 1) {
      let improved = false;
      for (let position = 0; position < current.numbers.length && !improved; position += 1) {
        for (let p = 0; p < pool.length; p += 1) {
          const replacement = pool[p];
          if (current.numbers.indexOf(replacement) >= 0) continue;
          const candidate = current.numbers.slice();
          candidate[position] = replacement;
          candidate.sort((a, b) => a - b);
          if (!satisfiesConstraints(candidate, constraints)) continue;
          const evaluation = Lotto.rawScore(candidate, context, 'default');
          const penalty = overlapWith(candidate, avoidSets) * (diversify ? 12 : 4);
          const score = Lotto.clamp(evaluation.score - penalty);
          if (score > current.score + 0.01) {
            current = { numbers: candidate, score: score, components: evaluation.components };
            improved = true;
            break;
          }
        }
      }
      if (!improved) break;
    }
    return current;
  }

  // ------------------------------------------------------- Caldi e freddi

  function temperatureMatches(item, filterId) {
    switch (filterId) {
      case 'hot': return Lotto.isHot(item);
      case 'cold': return Lotto.isCold(item);
      case 'overdue': return Lotto.isOverdue(item);
      case 'hotOverdue': return Lotto.isHot(item) && Lotto.isOverdue(item);
      case 'coldOverdue': return Lotto.isCold(item) && Lotto.isOverdue(item);
      case 'hotRecent': return Lotto.isHot(item) && item.currentDelay <= Math.max(Math.floor(item.averageDelay / 2), 3);
      case 'balanced': return !Lotto.isHot(item) && !Lotto.isCold(item) && !Lotto.isOverdue(item);
      default: return true;
    }
  }

  function temperatureTags(item) {
    const tags = [];
    if (Lotto.isHot(item)) tags.push('🔥 Hot');
    if (Lotto.isCold(item)) tags.push('❄️ Cold');
    if (Lotto.isOverdue(item)) tags.push('⏳ Overdue');
    if (!tags.length) tags.push('⚖️ Equilibrato');
    return tags;
  }

  function temperatureEntries(context, filterId, limit) {
    const items = [];
    for (let number = 1; number <= 90; number += 1) items.push(context.statistics.numbers[number]);
    const matching = items.filter((item) => temperatureMatches(item, filterId));
    const source = matching.length ? matching : items;

    const entries = source.map((item) => ({
      number: item.number,
      statistics: item,
      score: Lotto.scoreOf(context, item.number),
      tags: temperatureTags(item)
    }));

    entries.sort((a, b) => {
      switch (filterId) {
        case 'hot':
        case 'hotRecent':
          return b.statistics.trendRatio - a.statistics.trendRatio;
        case 'cold':
          return a.statistics.trendRatio - b.statistics.trendRatio;
        case 'overdue':
        case 'hotOverdue':
        case 'coldOverdue':
          return b.statistics.currentDelay - a.statistics.currentDelay;
        default:
          return b.score - a.score;
      }
    });
    return entries.slice(0, limit || 20);
  }

  /** Numeri ritardatari ordinati per ritardo attuale. */
  function overdueRanking(context, limit) {
    const items = [];
    for (let number = 1; number <= 90; number += 1) items.push(context.statistics.numbers[number]);
    items.sort((a, b) => b.currentDelay - a.currentDelay);
    return items.slice(0, limit || 90);
  }

  Object.assign(Lotto, {
    topPairs: topPairs,
    topTriples: topTriples,
    derivedConstraints: derivedConstraints,
    satisfiesConstraints: satisfiesConstraints,
    samplingWeights: samplingWeights,
    generateCombinations: generateCombinations,
    temperatureEntries: temperatureEntries,
    temperatureTags: temperatureTags,
    overdueRanking: overdueRanking
  });
})(typeof self !== 'undefined' ? self : this);
