/* AI EXPLAINER: traduce in italiano corrente il perché di una combinazione.

   Funziona interamente sul dispositivo: nessun dato lascia il telefono.
   Il linguaggio è deliberatamente descrittivo («ha avuto una frequenza superiore
   alla media») e mai predittivo («uscirà»). */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const pad = Lotto.pad;
  const fmt = Lotto.fmt;

  function numberLine(number, context) {
    const stats = Lotto.statsOf(context, number);
    const score = Lotto.scoreOf(context, number);
    const descriptors = [];

    if (stats.frequencyRatio > 1.08) {
      descriptors.push('frequenza superiore alla media del ' + fmt((stats.frequencyRatio - 1) * 100, 0) + '%');
    } else if (stats.frequencyRatio < 0.92) {
      descriptors.push('frequenza inferiore alla media del ' + fmt((1 - stats.frequencyRatio) * 100, 0) + '%');
    } else {
      descriptors.push('frequenza in linea con la media');
    }

    if (Lotto.isOverdue(stats)) {
      descriptors.push('ritardo elevato (' + stats.currentDelay + ' estrazioni contro una media di '
        + fmt(stats.averageDelay, 0) + ')');
    } else {
      descriptors.push('ritardo di ' + stats.currentDelay + ' estrazioni');
    }

    if (Lotto.isHot(stats)) descriptors.push('in crescita nel periodo recente');
    else if (Lotto.isCold(stats)) descriptors.push('in calo nel periodo recente');

    return '• ' + pad(number) + ' (indice ' + Math.round(score) + '): ' + descriptors.join(', ') + '.';
  }

  function summaryLine(combination, context, strategyId) {
    let text = 'Su ' + context.drawCount + ' estrazioni analizzate ('
      + Lotto.describeFilter(context.filter) + '), questa combinazione ottiene un indice statistico di '
      + Math.round(combination.score) + '/100 (' + Lotto.scoreBand(combination.score).label.toLowerCase() + ').';
    const strategy = Lotto.STRATEGIES.find((item) => item.id === strategyId);
    if (strategy) {
      text += ' La generazione ha seguito la strategia «' + strategy.name + '»: '
        + strategy.explanation.charAt(0).toLowerCase() + strategy.explanation.slice(1);
    }
    const labelled = Lotto.labelledComponents(combination.components);
    let dominant = labelled[0];
    labelled.forEach((item) => { if (item.value > dominant.value) dominant = item; });
    text += ' Il criterio che pesa di più è «' + dominant.label.toLowerCase() + '» ('
      + Math.round(dominant.value) + '/100).';
    return text;
  }

  function coOccurrenceLines(numbers, context) {
    const pairs = [];
    for (let i = 0; i < numbers.length - 1; i += 1) {
      for (let j = i + 1; j < numbers.length; j += 1) {
        pairs.push({
          a: numbers[i],
          b: numbers[j],
          count: Lotto.indexPairCount(context.occurrences, numbers[i], numbers[j]),
          lift: Lotto.indexPairLift(context.occurrences, numbers[i], numbers[j])
        });
      }
    }
    pairs.sort((x, y) => y.lift - x.lift);
    const lines = pairs.slice(0, 4).map((pair) => {
      let comparison;
      if (pair.lift > 1.1) comparison = 'il ' + fmt((pair.lift - 1) * 100, 0) + '% in più dell’atteso';
      else if (pair.lift < 0.9) comparison = 'il ' + fmt((1 - pair.lift) * 100, 0) + '% in meno dell’atteso';
      else comparison = 'in linea con l’atteso';
      return '• ' + pad(pair.a) + '–' + pad(pair.b) + ': ' + pair.count + ' uscite congiunte, ' + comparison + '.';
    });
    let averageLift = 0;
    pairs.forEach((pair) => { averageLift += pair.lift; });
    if (pairs.length) averageLift /= pairs.length;
    return lines.join('\n') + '\n\nRicorrenza media delle coppie interne: ' + fmt(averageLift, 2)
      + ' volte l’atteso casuale.';
  }

  function balanceLine(combination, context) {
    const numbers = combination.numbers;
    let sum = 0;
    let even = 0;
    let low = 0;
    const decades = {};
    numbers.forEach((number) => {
      sum += number;
      if (number % 2 === 0) even += 1;
      if (number <= 45) low += 1;
      decades[Math.min(Math.floor((number - 1) / 10), 8)] = true;
    });
    const expectedSum = (context.sumMean / context.gameInfo.drawnCount) * numbers.length;
    const sorted = numbers.slice().sort((a, b) => a - b);
    const averageGap = sorted.length > 1
      ? (sorted[sorted.length - 1] - sorted[0]) / (sorted.length - 1) : 0;

    let text = 'Pari ' + even + ' · dispari ' + (numbers.length - even) + ' · fascia 1–45: ' + low
      + ' · fascia 46–90: ' + (numbers.length - low) + ' · somma ' + sum
      + ' (media storica ' + fmt(expectedSum, 0) + ').';
    text += '\nI numeri coprono ' + Object.keys(decades).length
      + ' decine diverse, con una distanza media di ' + fmt(averageGap)
      + ' fra numeri consecutivi della combinazione.';
    text += combination.components.balance >= 70
      ? '\nNel complesso la combinazione è distribuita come lo sono tipicamente le estrazioni storiche.'
      : '\nNel complesso la combinazione è distribuita in modo meno tipico rispetto allo storico: questo abbassa la componente di equilibrio dell’indice.';
    return text;
  }

  function explain(combination, context, strategyId) {
    const sections = [
      { title: 'In sintesi', icon: '💬', body: summaryLine(combination, context, strategyId) },
      { title: 'Numero per numero', icon: '🔢',
        body: combination.numbers.map((number) => numberLine(number, context)).join('\n') }
    ];
    if (combination.numbers.length >= 2) {
      sections.push({ title: 'Come si comportano insieme', icon: '🔗',
        body: coOccurrenceLines(combination.numbers, context) });
    }
    sections.push({ title: 'Equilibrio della combinazione', icon: '⚖️',
      body: balanceLine(combination, context) });
    sections.push({ title: 'Cosa significa (e cosa non significa)', icon: '⚠️',
      body: Lotto.DISCLAIMER.score + '\n\n' + Lotto.DISCLAIMER.explainer });
    return sections;
  }

  /** Spiegazione di un singolo numero, usata nella scheda di dettaglio. */
  function explainNumber(number, context) {
    const stats = Lotto.statsOf(context, number);
    const matrix = Lotto.buildCoOccurrence(context.draws, context.gameInfo.drawnCount);
    const partners = Lotto.topPartners(matrix, number, 3);
    let text = numberLine(number, context);
    if (stats.lastSeen) {
      text += '\nUltima uscita: ' + new Date(stats.lastSeen).toLocaleDateString('it-IT',
        { day: 'numeric', month: 'long', year: 'numeric' }) + '.';
    }
    if (partners.length) {
      text += '\nNumeri con cui è uscito più spesso: '
        + partners.map((item) => pad(item.number) + ' (' + item.count + ' volte)').join(', ') + '.';
    }
    return text + '\n\n' + Lotto.DISCLAIMER.explainer;
  }

  Object.assign(Lotto, { explain: explain, explainNumber: explainNumber });
})(typeof self !== 'undefined' ? self : this);
