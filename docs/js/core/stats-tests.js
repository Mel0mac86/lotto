/* Test di significatività: chi quadro, binomiale, confronto fra due proporzioni.
   Porting di StatisticalTests.swift, con le funzioni speciali implementate a mano
   (JavaScript non ha lgamma né erfc nella libreria standard). */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  /** Logaritmo della funzione gamma (approssimazione di Lanczos, g = 7, n = 9). */
  function logGamma(x) {
    const coefficients = [
      0.99999999999980993, 676.5203681218851, -1259.1392167224028,
      771.32342877765313, -176.61502916214059, 12.507343278686905,
      -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7
    ];
    if (x < 0.5) {
      // Formula di riflessione.
      return Math.log(Math.PI / Math.sin(Math.PI * x)) - logGamma(1 - x);
    }
    const z = x - 1;
    let a = coefficients[0];
    const t = z + 7.5;
    for (let i = 1; i < 9; i += 1) a += coefficients[i] / (z + i);
    return 0.5 * Math.log(2 * Math.PI) + (z + 0.5) * Math.log(t) - t + Math.log(a);
  }

  /** Funzione gamma incompleta regolarizzata P(a, x). */
  function regularizedLowerGamma(a, x) {
    if (x <= 0 || a <= 0) return 0;
    if (x < a + 1) {
      // Sviluppo in serie.
      let sum = 1 / a;
      let term = sum;
      let n = 1;
      while (n < 500) {
        term *= x / (a + n);
        sum += term;
        if (Math.abs(term) < Math.abs(sum) * 1e-15) break;
        n += 1;
      }
      return sum * Math.exp(-x + a * Math.log(x) - logGamma(a));
    }
    // Frazione continua (algoritmo di Lentz) per Q(a, x).
    const tiny = 1e-300;
    let b = x + 1 - a;
    let c = 1 / tiny;
    let d = 1 / b;
    let h = d;
    let i = 1;
    while (i < 500) {
      const an = -i * (i - a);
      b += 2;
      d = an * d + b;
      if (Math.abs(d) < tiny) d = tiny;
      c = b + an / c;
      if (Math.abs(c) < tiny) c = tiny;
      d = 1 / d;
      const delta = d * c;
      h *= delta;
      if (Math.abs(delta - 1) < 1e-15) break;
      i += 1;
    }
    return 1 - Math.exp(-x + a * Math.log(x) - logGamma(a)) * h;
  }

  /**
   * Funzione degli errori complementare, ricavata dalla gamma incompleta:
   * per x ≥ 0 vale erfc(x) = 1 − P(1/2, x²), e per x < 0 erfc(x) = 1 + P(1/2, x²).
   * Riusare `regularizedLowerGamma` evita di introdurre una seconda
   * approssimazione con un'accuratezza tutta da verificare.
   */
  function erfc(x) {
    const gamma = regularizedLowerGamma(0.5, x * x);
    return x >= 0 ? 1 - gamma : 1 + gamma;
  }

  function erf(x) {
    return 1 - erfc(x);
  }

  /** Funzione di ripartizione della normale standard. */
  function standardNormalCDF(x) {
    return 0.5 * erfc(-x / Math.SQRT2);
  }

  /** p-value della distribuzione chi quadro: P(X > statistic). */
  function chiSquarePValue(statistic, degreesOfFreedom) {
    if (statistic <= 0 || degreesOfFreedom <= 0) return 1;
    return 1 - regularizedLowerGamma(degreesOfFreedom / 2, statistic / 2);
  }

  function formatP(value) {
    if (value < 0.0001) return '< 0,0001';
    return value.toFixed(4).replace('.', ',');
  }

  /** Test di bontà di adattamento. */
  function chiSquareGoodnessOfFit(observed, expected, name) {
    let statistic = 0;
    let cells = 0;
    for (let i = 0; i < expected.length; i += 1) {
      if (expected[i] <= 0) continue;
      const difference = observed[i] - expected[i];
      statistic += (difference * difference) / expected[i];
      cells += 1;
    }
    const degrees = Math.max(cells - 1, 1);
    const p = chiSquarePValue(statistic, degrees);
    return {
      name: name,
      statistic: statistic,
      degreesOfFreedom: degrees,
      pValue: p,
      isSignificant: p < 0.05,
      interpretation: p < 0.05
        ? 'Le frequenze osservate si discostano dal modello casuale in misura statisticamente significativa (p = ' + formatP(p) + ').'
        : 'Le frequenze osservate sono compatibili con un processo casuale (p = ' + formatP(p) + ').'
    };
  }

  /** Test binomiale con approssimazione normale e correzione di continuità. */
  function binomialTest(successes, trials, probability, name) {
    if (trials <= 0 || probability <= 0 || probability >= 1) {
      return { name: name, statistic: 0, degreesOfFreedom: null, pValue: 1, isSignificant: false,
        interpretation: 'Dati insufficienti per il test.' };
    }
    const mean = trials * probability;
    const sigma = Math.sqrt(trials * probability * (1 - probability));
    if (sigma <= 0) {
      return { name: name, statistic: 0, degreesOfFreedom: null, pValue: 1, isSignificant: false,
        interpretation: 'Varianza nulla: test non applicabile.' };
    }
    const z = Math.max(Math.abs(successes - mean) - 0.5, 0) / sigma;
    const p = 2 * (1 - standardNormalCDF(z));
    const direction = successes > mean ? 'superiore' : 'inferiore';
    return {
      name: name,
      statistic: z,
      degreesOfFreedom: null,
      pValue: p,
      isSignificant: p < 0.05,
      interpretation: p < 0.05
        ? 'Il risultato osservato è ' + direction + ' all’atteso in modo statisticamente significativo (z = '
          + z.toFixed(2).replace('.', ',') + ', p = ' + formatP(p) + ').'
        : 'Il risultato osservato è compatibile con l’atteso casuale (z = '
          + z.toFixed(2).replace('.', ',') + ', p = ' + formatP(p) + ').'
    };
  }

  /** Confronto fra due proporzioni: strategia contro baseline casuale. */
  function twoProportionZTest(successesA, trialsA, successesB, trialsB, name) {
    if (trialsA <= 0 || trialsB <= 0) {
      return { name: name, statistic: 0, degreesOfFreedom: null, pValue: 1, isSignificant: false,
        interpretation: 'Dati insufficienti per il confronto.' };
    }
    const pA = successesA / trialsA;
    const pB = successesB / trialsB;
    const pooled = (successesA + successesB) / (trialsA + trialsB);
    const standardError = Math.sqrt(pooled * (1 - pooled) * (1 / trialsA + 1 / trialsB));
    if (standardError <= 0) {
      return { name: name, statistic: 0, degreesOfFreedom: null, pValue: 1, isSignificant: false,
        interpretation: 'Nessuna differenza misurabile fra le due serie.' };
    }
    const z = (pA - pB) / standardError;
    const p = 2 * (1 - standardNormalCDF(Math.abs(z)));
    let interpretation;
    if (p >= 0.05) {
      interpretation = 'La differenza rispetto alla baseline casuale non è statisticamente significativa (p = '
        + formatP(p) + '). ' + Lotto.DISCLAIMER.noEdge;
    } else if (z > 0) {
      interpretation = 'La strategia mostra una differenza positiva statisticamente significativa nel periodo testato (p = '
        + formatP(p) + '). Il risultato riguarda il campione analizzato e non implica capacità predittiva.';
    } else {
      interpretation = 'La strategia ha fatto peggio della baseline casuale in modo statisticamente significativo (p = '
        + formatP(p) + ').';
    }
    return { name: name, statistic: z, degreesOfFreedom: null, pValue: p, isSignificant: p < 0.05, interpretation: interpretation };
  }

  Object.assign(Lotto, {
    logGamma: logGamma,
    regularizedLowerGamma: regularizedLowerGamma,
    erf: erf,
    erfc: erfc,
    standardNormalCDF: standardNormalCDF,
    chiSquarePValue: chiSquarePValue,
    chiSquareGoodnessOfFit: chiSquareGoodnessOfFit,
    binomialTest: binomialTest,
    twoProportionZTest: twoProportionZTest,
    formatP: formatP
  });
})(typeof self !== 'undefined' ? self : this);
