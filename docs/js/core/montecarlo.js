/* Simulazioni Monte Carlo di estrazioni puramente casuali, per confrontare
   i pattern storici con ciò che il caso produce. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  /** Batteria di test sui dati storici, confrontati con il modello uniforme. */
  function randomnessTests(context) {
    if (context.drawCount === 0) return [];
    const drawn = context.gameInfo.drawnCount;
    const totalNumbers = context.drawCount * drawn;

    const observedFrequencies = [];
    for (let n = 1; n <= 90; n += 1) observedFrequencies.push(context.statistics.numbers[n].occurrences);
    const frequencyTest = Lotto.chiSquareGoodnessOfFit(
      observedFrequencies,
      new Array(90).fill(totalNumbers / 90),
      'Uniformità delle frequenze (1–90)');

    const observedDecades = [];
    for (let d = 0; d <= 8; d += 1) observedDecades.push(context.statistics.decadeDistribution[d] || 0);
    const decadeTest = Lotto.chiSquareGoodnessOfFit(
      observedDecades,
      new Array(9).fill(totalNumbers / 9),
      'Uniformità delle decine');

    // Ogni cifra delle unità (0…9) copre esattamente 9 numeri fra 1 e 90.
    const observedUnits = [];
    for (let u = 0; u <= 9; u += 1) observedUnits.push(context.statistics.unitDistribution[u] || 0);
    const unitTest = Lotto.chiSquareGoodnessOfFit(
      observedUnits,
      new Array(10).fill(totalNumbers / 10),
      'Uniformità delle unità');

    let totalEven = 0;
    let totalLow = 0;
    context.draws.forEach((draw) => {
      totalEven += Lotto.evenCount(draw);
      totalLow += Lotto.lowCount(draw);
    });
    const parityTest = Lotto.binomialTest(totalEven, totalNumbers, 0.5, 'Distribuzione pari/dispari');
    const rangeTest = Lotto.binomialTest(totalLow, totalNumbers, 0.5, 'Distribuzione 1–45 / 46–90');

    return [frequencyTest, decadeTest, unitTest, parityTest, rangeTest];
  }

  /**
   * Esegue la simulazione. `onProgress` riceve valori 0…1.
   * Gli accumulatori del ciclo caldo sono array tipizzati: un dizionario qui
   * costerebbe milioni di hash su una simulazione da un milione di estrazioni.
   */
  function runMonteCarlo(context, iterations, seed, onProgress) {
    const started = Date.now();
    const drawn = context.gameInfo.drawnCount;
    const generator = new Lotto.SeededRandom(seed || 20260101);

    const counts = new Int32Array(91);
    const lastSeen = new Int32Array(91).fill(-1);
    const maxDelays = new Int32Array(91);
    const decadeCounts = new Int32Array(9);
    const evenCounts = new Int32Array(drawn + 1);
    const sumCounts = new Map();
    const pool = new Int32Array(90);
    for (let i = 0; i < 90; i += 1) pool[i] = i + 1;

    const reportEvery = Math.max(Math.floor(iterations / 100), 1);

    for (let iteration = 0; iteration < iterations; iteration += 1) {
      // Estrazione senza reimmissione: Fisher–Yates parziale.
      for (let position = 0; position < drawn; position += 1) {
        const swap = position + generator.nextInt(90 - position);
        const temp = pool[position];
        pool[position] = pool[swap];
        pool[swap] = temp;
      }
      let sum = 0;
      let even = 0;
      for (let position = 0; position < drawn; position += 1) {
        const number = pool[position];
        counts[number] += 1;
        sum += number;
        if (number % 2 === 0) even += 1;
        decadeCounts[Math.min(Math.floor((number - 1) / 10), 8)] += 1;
        if (lastSeen[number] >= 0) {
          const delay = iteration - lastSeen[number] - 1;
          if (delay > maxDelays[number]) maxDelays[number] = delay;
        }
        lastSeen[number] = iteration;
      }
      sumCounts.set(sum, (sumCounts.get(sum) || 0) + 1);
      evenCounts[even] += 1;

      if (onProgress && iteration % reportEvery === 0) onProgress(iteration / iterations);
    }
    if (onProgress) onProgress(1);

    const simulatedFrequency = {};
    const historicalFrequency = {};
    const historicalMaxDelays = [];
    const simulatedMaxDelays = [];
    for (let number = 1; number <= 90; number += 1) {
      simulatedFrequency[number] = counts[number] / iterations;
      historicalFrequency[number] = context.statistics.numbers[number].frequency;
      historicalMaxDelays.push(context.statistics.numbers[number].maxDelay);
      simulatedMaxDelays.push(maxDelays[number]);
    }

    const historicalSums = {};
    const historicalEven = {};
    const historicalDecades = {};
    context.draws.forEach((draw) => {
      const sum = Lotto.drawSum(draw);
      historicalSums[sum] = (historicalSums[sum] || 0) + 1;
      const even = Lotto.evenCount(draw);
      historicalEven[even] = (historicalEven[even] || 0) + 1;
      draw.numbers.forEach((number) => {
        const decade = Math.min(Math.floor((number - 1) / 10), 8);
        historicalDecades[decade] = (historicalDecades[decade] || 0) + 1;
      });
    });

    const simulatedSums = {};
    sumCounts.forEach((value, key) => { simulatedSums[key] = value; });
    const simulatedEven = {};
    for (let e = 0; e < evenCounts.length; e += 1) if (evenCounts[e] > 0) simulatedEven[e] = evenCounts[e];
    const simulatedDecades = {};
    for (let d = 0; d < 9; d += 1) simulatedDecades[d] = decadeCounts[d];

    const tests = randomnessTests(context);
    const significant = tests.filter((test) => test.isSignificant);
    const conclusion = significant.length === 0
      ? 'I pattern osservati nei dati storici sono compatibili con un processo casuale: nessuno dei test eseguiti ha rilevato scostamenti statisticamente significativi.'
      : 'Alcuni test segnalano scostamenti dalla casualità (' + significant.map((t) => t.name).join(', ')
        + '). Con molti test eseguiti in parallelo qualche scostamento è atteso anche in dati puramente casuali: va interpretato con prudenza e non implica capacità predittiva.';

    return {
      iterations: iterations,
      drawnPerDraw: drawn,
      simulatedFrequency: simulatedFrequency,
      historicalFrequency: historicalFrequency,
      simulatedSums: simulatedSums,
      historicalSums: historicalSums,
      simulatedEven: simulatedEven,
      historicalEven: historicalEven,
      simulatedDecades: simulatedDecades,
      historicalDecades: historicalDecades,
      simulatedMaxDelays: simulatedMaxDelays,
      historicalMaxDelays: historicalMaxDelays,
      tests: tests,
      conclusion: conclusion,
      elapsed: (Date.now() - started) / 1000
    };
  }

  Object.assign(Lotto, {
    randomnessTests: randomnessTests,
    runMonteCarlo: runMonteCarlo
  });
})(typeof self !== 'undefined' ? self : this);
