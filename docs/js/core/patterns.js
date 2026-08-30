/* TROVA PATTERN: ricerca automatica di regolarità nei dati storici, con la
   distinzione esplicita fra ciò che è statisticamente significativo e ciò che è
   compatibile con la normale variabilità casuale. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  const CATEGORIES = [
    { id: 'frequency', name: 'Frequenze', icon: '📊' },
    { id: 'coOccurrence', name: 'Co-occorrenze', icon: '🔗' },
    { id: 'delay', name: 'Ritardi', icon: '⏳' },
    { id: 'distribution', name: 'Distribuzioni', icon: '⚖️' },
    { id: 'temporal', name: 'Pattern temporali', icon: '📅' },
    { id: 'cluster', name: 'Cluster', icon: '🧩' },
    { id: 'anomaly', name: 'Anomalie', icon: '⚠️' }
  ];

  function binomial(n, k) {
    if (k < 0 || k > n) return 0;
    let result = 1;
    for (let i = 0; i < k; i += 1) result *= (n - i) / (i + 1);
    return result;
  }

  /** Probabilità che una combinazione di k numeri su 90 contenga una coppia consecutiva. */
  function consecutiveProbability(drawn) {
    if (drawn < 2 || 90 - drawn + 1 < drawn) return 0;
    const total = binomial(90, drawn);
    if (total <= 0) return 0;
    return 1 - binomial(90 - drawn + 1, drawn) / total;
  }

  function analyzePatterns(context) {
    if (context.drawCount < 30) {
      return [{
        category: 'anomaly',
        title: 'Dati insufficienti',
        detail: 'Servono almeno 30 estrazioni nel periodo selezionato per una ricerca di pattern attendibile.',
        test: null,
        assessment: 'Analisi non eseguita.',
        isNoteworthy: false
      }];
    }

    const patterns = [];
    const drawn = context.gameInfo.drawnCount;
    const totalNumbers = context.drawCount * drawn;

    // --- Frequenze
    const observed = [];
    for (let n = 1; n <= 90; n += 1) observed.push(context.statistics.numbers[n].occurrences);
    const frequencyTest = Lotto.chiSquareGoodnessOfFit(observed, new Array(90).fill(totalNumbers / 90),
      'Uniformità delle frequenze');
    patterns.push({
      category: 'frequency',
      title: 'Distribuzione complessiva delle frequenze',
      detail: 'Chi quadro = ' + Lotto.fmt(frequencyTest.statistic, 2) + ' su '
        + frequencyTest.degreesOfFreedom + ' gradi di libertà.',
      test: frequencyTest,
      assessment: frequencyTest.interpretation,
      isNoteworthy: frequencyTest.isSignificant
    });

    const probability = drawn / 90;
    const outliers = [];
    for (let n = 1; n <= 90; n += 1) {
      const test = Lotto.binomialTest(context.statistics.numbers[n].occurrences, context.drawCount,
        probability, 'Numero ' + n);
      if (test.pValue < 0.01) outliers.push({ number: n, test: test });
    }
    if (!outliers.length) {
      patterns.push({
        category: 'frequency',
        title: 'Nessun numero fuori scala',
        detail: 'Nessun numero si discosta dall’atteso oltre la soglia dell’1%.',
        test: null,
        assessment: 'Il comportamento dei singoli numeri è compatibile con il caso.',
        isNoteworthy: false
      });
    } else {
      // Con 90 test all'1% ci si attendono circa 0,9 falsi positivi per puro caso.
      const expectedFalsePositives = 90 * 0.01;
      patterns.push({
        category: 'frequency',
        title: 'Numeri con frequenza estrema',
        detail: 'Numeri segnalati: ' + outliers.map((item) => Lotto.pad(item.number)).join(', ') + '.',
        test: outliers[0].test,
        assessment: 'Sono stati eseguiti 90 test contemporaneamente: per puro caso ce ne si attendono circa '
          + Lotto.fmt(expectedFalsePositives) + ' al livello dell’1%. Con ' + outliers.length
          + ' segnalazioni il risultato ' + (outliers.length > 3
            ? 'merita attenzione ma resta descrittivo'
            : 'è compatibile con la molteplicità dei test') + '.',
        isNoteworthy: outliers.length > 3
      });
    }

    // --- Co-occorrenze
    const expectedPair = context.occurrences.expectedPair;
    if (expectedPair > 0) {
      const pairProbability = (drawn * (drawn - 1)) / (90 * 89);
      const extremes = [];
      for (let index = 0; index < Lotto.PAIR_COUNT; index += 1) {
        const count = context.occurrences.pairCounts[index];
        if (count < 4 || count <= expectedPair * 1.6) continue;
        const test = Lotto.binomialTest(count, context.drawCount, pairProbability, 'Ambo');
        if (test.pValue < 0.001) {
          const pair = Lotto.pairAt(index);
          extremes.push({ a: pair[0], b: pair[1], count: count });
        }
      }
      // 4.005 coppie testate: allo 0,1% ci si attendono ~4 falsi positivi.
      const expectedFalsePositives = Lotto.PAIR_COUNT * 0.001;
      if (!extremes.length) {
        patterns.push({
          category: 'coOccurrence',
          title: 'Co-occorrenze in linea con l’atteso',
          detail: 'Uscite congiunte attese per coppia: ' + Lotto.fmt(expectedPair, 2)
            + '. Nessuna coppia supera la soglia di significatività.',
          test: null,
          assessment: 'Le co-occorrenze osservate sono compatibili con estrazioni indipendenti.',
          isNoteworthy: false
        });
      } else {
        extremes.sort((x, y) => y.count - x.count);
        patterns.push({
          category: 'coOccurrence',
          title: 'Coppie con ricorrenza superiore all’atteso',
          detail: extremes.slice(0, 5).map((item) => Lotto.pad(item.a) + '–' + Lotto.pad(item.b)
            + ' (' + item.count + ' uscite)').join(', '),
          test: null,
          assessment: 'Sono state testate tutte le ' + Lotto.PAIR_COUNT
            + ' coppie: al livello dello 0,1% ci si attendono circa ' + Math.round(expectedFalsePositives)
            + ' segnalazioni per puro caso. Con ' + extremes.length + ' coppie segnalate il risultato '
            + (extremes.length > expectedFalsePositives * 2
              ? 'è superiore all’atteso, pur restando descrittivo'
              : 'è pienamente compatibile con il caso') + '.',
          isNoteworthy: extremes.length > expectedFalsePositives * 2
        });
      }
    }

    // --- Ritardi
    let delaySum = 0;
    let extreme = context.statistics.numbers[1];
    for (let n = 1; n <= 90; n += 1) {
      const item = context.statistics.numbers[n];
      delaySum += item.averageDelay;
      if (item.delayRatio > extreme.delayRatio) extreme = item;
    }
    const observedMean = delaySum / 90;
    // In un processo geometrico il ritardo atteso è (1-p)/p con p = k/90.
    const theoreticalMean = (1 - probability) / probability;
    const delayOff = Math.abs(observedMean - theoreticalMean) >= theoreticalMean * 0.15;
    patterns.push({
      category: 'delay',
      title: 'Ritardo medio osservato',
      detail: 'Ritardo medio osservato: ' + Lotto.fmt(observedMean)
        + ' estrazioni. Valore teorico per un processo casuale: ' + Lotto.fmt(theoreticalMean) + '.',
      test: null,
      assessment: delayOff
        ? 'Il ritardo medio si discosta dal valore teorico: verificare la completezza dello storico importato.'
        : 'Il comportamento dei ritardi è quello atteso da estrazioni indipendenti.',
      isNoteworthy: delayOff
    });
    patterns.push({
      category: 'delay',
      title: 'Ritardo attuale più elevato',
      detail: 'Il ' + Lotto.pad(extreme.number) + ' manca da ' + extreme.currentDelay
        + ' estrazioni, pari al ' + Lotto.fmt(extreme.delayRatio * 100, 0)
        + '% del suo massimo storico (' + extreme.maxDelay + ').',
      test: null,
      assessment: Lotto.DISCLAIMER.delay,
      isNoteworthy: false
    });

    // --- Distribuzioni
    let evenTotal = 0;
    context.draws.forEach((draw) => { evenTotal += Lotto.evenCount(draw); });
    const parity = Lotto.binomialTest(evenTotal, totalNumbers, 0.5, 'Pari/dispari');
    patterns.push({
      category: 'distribution',
      title: 'Distribuzione pari/dispari',
      detail: 'Pari: ' + evenTotal + ' su ' + totalNumbers + ' numeri estratti ('
        + Lotto.fmt((evenTotal / totalNumbers) * 100, 2) + '%).',
      test: parity,
      assessment: parity.interpretation,
      isNoteworthy: parity.isSignificant
    });

    if (context.statistics.sums.length) {
      let sumTotal = 0;
      let minSum = Infinity;
      let maxSum = -Infinity;
      context.statistics.sums.forEach((value) => {
        sumTotal += value;
        if (value < minSum) minSum = value;
        if (value > maxSum) maxSum = value;
      });
      const mean = sumTotal / context.statistics.sums.length;
      const theoretical = drawn * 45.5;
      const sumOff = Math.abs(mean - theoretical) >= drawn * 1.5;
      patterns.push({
        category: 'distribution',
        title: 'Somma delle combinazioni',
        detail: 'Somma media osservata: ' + Lotto.fmt(mean) + '. Somma media teorica: '
          + Lotto.fmt(theoretical) + '. Intervallo osservato: ' + minSum + '–' + maxSum + '.',
        test: null,
        assessment: sumOff
          ? 'La somma media si discosta dal valore teorico: possibile storico parziale o non uniforme.'
          : 'La distribuzione delle somme è quella attesa da estrazioni casuali.',
        isNoteworthy: sumOff
      });
    }

    const consecutiveRate = context.statistics.drawsWithConsecutives / Math.max(context.drawCount, 1);
    const theoreticalConsecutive = consecutiveProbability(drawn);
    patterns.push({
      category: 'distribution',
      title: 'Numeri consecutivi',
      detail: 'Estrazioni con almeno una coppia consecutiva: ' + Lotto.fmt(consecutiveRate * 100)
        + '% (atteso teorico ' + Lotto.fmt(theoreticalConsecutive * 100) + '%).',
      test: Lotto.binomialTest(context.statistics.drawsWithConsecutives, context.drawCount,
        theoreticalConsecutive, 'Coppie consecutive'),
      assessment: 'Le coppie consecutive sono molto più comuni di quanto l’intuizione suggerisca: è un effetto noto della combinatoria, non un pattern.',
      isNoteworthy: false
    });

    // --- Stagionalità
    const months = Object.keys(context.statistics.byMonth);
    if (months.length >= 6) {
      const drawsPerMonth = {};
      context.draws.forEach((draw) => {
        const month = Lotto.monthOf(draw);
        drawsPerMonth[month] = (drawsPerMonth[month] || 0) + 1;
      });
      const observedMonthly = [];
      const expectedMonthly = [];
      for (let month = 1; month <= 12; month += 1) {
        const counts = context.statistics.byMonth[month] || {};
        let total = 0;
        Object.keys(counts).forEach((key) => { total += counts[key]; });
        observedMonthly.push(total);
        expectedMonthly.push((drawsPerMonth[month] || 0) * drawn);
      }
      const test = Lotto.chiSquareGoodnessOfFit(observedMonthly, expectedMonthly, 'Stagionalità mensile');
      patterns.push({
        category: 'temporal',
        title: 'Stagionalità delle uscite',
        detail: 'Confronto fra uscite mensili osservate e attese in base al numero di estrazioni per mese.',
        test: test,
        assessment: test.isSignificant
          ? 'Emerge uno scostamento mensile: prima di interpretarlo verificare che lo storico copra tutti i mesi in modo omogeneo.'
          : 'Nessuna stagionalità rilevabile: le uscite mensili riflettono soltanto quante estrazioni ci sono state in ciascun mese.',
        isNoteworthy: test.isSignificant
      });
    }

    // --- Cluster
    const clusters = Lotto.clusterNumbers(context, 3);
    if (clusters.length) {
      patterns.push({
        category: 'cluster',
        title: 'Raggruppamento dei numeri per profilo statistico',
        detail: clusters.map((cluster) => cluster.title + ': ' + cluster.numbers.length + ' numeri ('
          + cluster.numbers.slice(0, 8).map(Lotto.pad).join(', ')
          + (cluster.numbers.length > 8 ? '…' : '') + ')').join('\n'),
        test: null,
        assessment: 'Il clustering descrive come i numeri si somigliano per frequenza, ritardo e trend nel periodo osservato. Raggruppamenti di questo tipo emergono anche da dati puramente casuali e non indicano un comportamento futuro.',
        isNoteworthy: false
      });
    }

    patterns.push({
      category: 'anomaly',
      title: 'Nota sulla molteplicità dei test',
      detail: 'In questa analisi sono stati eseguiti migliaia di confronti (90 numeri, 4.005 coppie, distribuzioni, stagionalità).',
      test: null,
      assessment: 'Quando si eseguono molti test contemporaneamente, alcuni risultati «significativi» compaiono per puro caso. Ogni pattern qui elencato va letto come descrizione del passato, mai come indicazione sul futuro.',
      isNoteworthy: false
    });

    return patterns;
  }

  Object.assign(Lotto, {
    PATTERN_CATEGORIES: CATEGORIES,
    consecutiveProbability: consecutiveProbability,
    analyzePatterns: analyzePatterns
  });
})(typeof self !== 'undefined' ? self : this);
