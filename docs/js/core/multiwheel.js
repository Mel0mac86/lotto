/* Analisi TUTTE LE RUOTE: numeri, ambi, terni e cinquina con segnali
   statistici coerenti su più ruote contemporaneamente. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  /** Costruisce un contesto per ciascuna ruota che abbia dati nel periodo. */
  function buildWheelContexts(filter, allDraws, weights) {
    const contexts = {};
    Lotto.WHEEL_IDS.forEach((wheel) => {
      const wheelFilter = Object.assign({}, filter, { wheel: wheel });
      const context = Lotto.buildContext(wheelFilter, allDraws, weights);
      if (!context.isEmpty) contexts[wheel] = context;
    });
    return contexts;
  }

  /** Numeri con indice statistico sopra soglia su più ruote. */
  function multiWheelNumbers(contexts, threshold, limit) {
    const wheels = Object.keys(contexts);
    if (!wheels.length) return [];
    const totalWheels = wheels.length;
    const scoreThreshold = threshold === undefined ? 65 : threshold;
    const results = [];

    for (let number = 1; number <= 90; number += 1) {
      const active = [];
      let scoreSum = 0;
      let occurrences = 0;
      let delaySum = 0;
      let best = null;

      wheels.forEach((wheel) => {
        const context = contexts[wheel];
        const score = Lotto.scoreOf(context, number);
        const stats = Lotto.statsOf(context, number);
        occurrences += stats.occurrences;
        delaySum += stats.currentDelay;
        if (score >= scoreThreshold) {
          active.push(wheel);
          scoreSum += score;
        }
        if (!best || score > best.score) best = { wheel: wheel, score: score };
      });

      if (!active.length) continue;
      const averageScore = scoreSum / active.length;
      // Il bonus multi-ruota premia la coerenza del segnale, non la sua forza su una sola ruota.
      const coverage = active.length / totalWheels;
      results.push({
        number: number,
        wheels: active.sort(),
        wheelCodes: active.map(Lotto.wheelCode).join(' '),
        totalOccurrences: occurrences,
        averageScore: averageScore,
        score: Lotto.clamp(averageScore * 0.7 + coverage * 100 * 0.3),
        averageDelay: delaySum / totalWheels,
        bestWheel: best ? best.wheel : null
      });
    }

    results.sort((a, b) => b.score - a.score);
    return results.slice(0, limit || 30);
  }

  /** Ambi che ricorrono su più ruote. */
  function multiWheelPairs(contexts, limit) {
    const wheels = Object.keys(contexts);
    if (!wheels.length) return [];
    const aggregate = new Map();
    let expectedTotal = 0;

    wheels.forEach((wheel) => {
      const context = contexts[wheel];
      expectedTotal += context.occurrences.expectedPair;

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

      for (let index = 0; index < Lotto.PAIR_COUNT; index += 1) {
        const count = context.occurrences.pairCounts[index];
        if (count === 0) continue;
        const pair = Lotto.pairAt(index);
        let entry = aggregate.get(index);
        if (!entry) {
          entry = { wheels: [], count: 0, recent: 0, delaySum: 0, scoreSum: 0 };
          aggregate.set(index, entry);
        }
        entry.wheels.push(wheel);
        entry.count += count;
        entry.recent += recentCounts[index];
        entry.delaySum += Lotto.indexPairDelay(context.occurrences, pair[0], pair[1]);
        entry.scoreSum += (Lotto.scoreOf(context, pair[0]) + Lotto.scoreOf(context, pair[1])) / 2;
      }
    });

    const totalWheels = wheels.length;
    const results = [];
    aggregate.forEach((entry, index) => {
      const pair = Lotto.pairAt(index);
      const coverage = entry.wheels.length / totalWheels;
      const averageNumberScore = entry.scoreSum / entry.wheels.length;
      const lift = expectedTotal > 0 ? entry.count / expectedTotal : 0;
      const liftScore = Lotto.clamp(50 * lift);
      results.push({
        numbers: pair,
        wheels: entry.wheels.slice().sort(),
        totalJointCount: entry.count,
        recentJointCount: entry.recent,
        averageDelay: entry.delaySum / entry.wheels.length,
        score: Lotto.clamp(liftScore * 0.4 + averageNumberScore * 0.3 + coverage * 100 * 0.3)
      });
    });

    results.sort((a, b) => b.score - a.score);
    return results.slice(0, limit || 10).map(withMultiWheelReasons);
  }

  /** Terni che ricorrono su più ruote. */
  function multiWheelTriples(contexts, limit) {
    const wheels = Object.keys(contexts);
    if (!wheels.length) return [];
    const aggregate = new Map();
    let expectedTotal = 0;

    wheels.forEach((wheel) => {
      const context = contexts[wheel];
      expectedTotal += context.occurrences.expectedTriple;
      context.occurrences.triples.forEach((entry, key) => {
        let accumulated = aggregate.get(key);
        if (!accumulated) {
          accumulated = { wheels: [], count: 0, delaySum: 0, scoreSum: 0 };
          aggregate.set(key, accumulated);
        }
        accumulated.wheels.push(wheel);
        accumulated.count += entry.count;
        accumulated.delaySum += context.drawCount - 1 - entry.lastIndex;
        const numbers = Lotto.decodeTriple(key);
        accumulated.scoreSum += (Lotto.scoreOf(context, numbers[0])
          + Lotto.scoreOf(context, numbers[1]) + Lotto.scoreOf(context, numbers[2])) / 3;
      });
    });

    const totalWheels = wheels.length;
    const keep = limit || 10;
    const best = [];
    aggregate.forEach((entry, key) => {
      const numbers = Lotto.decodeTriple(key);
      const coverage = entry.wheels.length / totalWheels;
      const averageNumberScore = entry.scoreSum / entry.wheels.length;
      const lift = expectedTotal > 0 ? entry.count / expectedTotal : 0;
      const score = Lotto.clamp(Lotto.clamp(50 * lift) * 0.35 + averageNumberScore * 0.30 + coverage * 100 * 0.35);
      if (best.length >= keep && score <= best[best.length - 1].score) return;
      const item = {
        numbers: numbers,
        wheels: entry.wheels.slice().sort(),
        totalJointCount: entry.count,
        recentJointCount: 0,
        averageDelay: entry.delaySum / entry.wheels.length,
        score: score
      };
      let position = best.length;
      while (position > 0 && best[position - 1].score < score) position -= 1;
      best.splice(position, 0, item);
      if (best.length > keep) best.length = keep;
    });

    return best.map(withMultiWheelReasons);
  }

  function withMultiWheelReasons(item) {
    item.wheelCount = item.wheels.length;
    item.reasons = [
      (item.numbers.length === 2 ? 'Uscita congiunta' : 'Terna osservata') + ' su ' + item.wheels.length
        + ' ruote (' + item.wheels.map(Lotto.wheelCode).join(', ') + ').',
      'Uscite congiunte complessive: ' + item.totalJointCount
        + (item.recentJointCount ? ', di cui ' + item.recentJointCount + ' nella parte recente del periodo' : '') + '.',
      'Ritardo medio sulle ruote interessate: ' + Lotto.fmt(item.averageDelay) + ' estrazioni.',
      Lotto.DISCLAIMER.explainer
    ];
    return item;
  }

  /** CINQUINA MULTI-RUOTA costruita sui numeri con segnali su più ruote. */
  function multiWheelCombination(contexts, size, seed) {
    const candidates = multiWheelNumbers(contexts, 60, 25);
    const wheels = Object.keys(contexts);
    if (candidates.length < (size || 5) || !wheels.length) return null;

    // La ruota con più estrazioni fa da riferimento per equilibrio e spiegazioni.
    let reference = contexts[wheels[0]];
    wheels.forEach((wheel) => {
      if (contexts[wheel].drawCount > reference.drawCount) reference = contexts[wheel];
    });

    const combinationSize = size || 5;
    const generator = new Lotto.SeededRandom(seed || Date.now());
    const constraints = Lotto.derivedConstraints(reference, combinationSize);
    const weights = candidates.map((item) => Math.max(item.score, 1));
    let best = null;

    for (let attempt = 0; attempt < 3000; attempt += 1) {
      const indices = generator.weightedSample(weights, combinationSize);
      if (indices.length !== combinationSize) continue;
      const numbers = indices.map((index) => candidates[index].number).sort((a, b) => a - b);
      if (!Lotto.satisfiesConstraints(numbers, constraints)) continue;
      let multiScore = 0;
      numbers.forEach((number) => {
        const candidate = candidates.find((item) => item.number === number);
        if (candidate) multiScore += candidate.score;
      });
      multiScore /= combinationSize;
      const balance = Lotto.balanceScore(numbers, reference);
      const score = multiScore * 0.75 + balance * 0.25;
      if (!best || score > best.score) best = { numbers: numbers, score: score };
    }
    if (!best) return null;

    const evaluation = Lotto.rawScore(best.numbers, reference, 'default');
    const reasons = ['Combinazione costruita sui numeri con segnali statistici presenti su più ruote.'];
    const involved = {};
    best.numbers.forEach((number) => {
      const candidate = candidates.find((item) => item.number === number);
      if (!candidate) return;
      candidate.wheels.forEach((wheel) => { involved[wheel] = true; });
      reasons.push(Lotto.pad(number) + ' — segnalato su ' + candidate.wheels.length + ' ruote ('
        + candidate.wheelCodes + '), indice medio ' + Math.round(candidate.averageScore) + '.');
    });
    reasons.push(Lotto.DISCLAIMER.explainer);

    return {
      combination: {
        numbers: best.numbers,
        score: Lotto.clamp(best.score),
        components: evaluation.components,
        reasons: reasons
      },
      wheels: Object.keys(involved).sort()
    };
  }

  Object.assign(Lotto, {
    buildWheelContexts: buildWheelContexts,
    multiWheelNumbers: multiWheelNumbers,
    multiWheelPairs: multiWheelPairs,
    multiWheelTriples: multiWheelTriples,
    multiWheelCombination: multiWheelCombination
  });
})(typeof self !== 'undefined' ? self : this);
