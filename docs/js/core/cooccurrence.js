/* Co-occorrenze fra numeri: matrice triangolare delle coppie e indice delle terne.
   Porting di CoOccurrenceMatrix.swift e SetOccurrenceIndex.swift. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};
  const MAX_NUMBER = 90;
  const PAIR_COUNT = (MAX_NUMBER * (MAX_NUMBER - 1)) / 2; // 4005

  /** Indice lineare della coppia (a, b), a ≠ b, entrambi in 1…90. */
  function pairIndex(a, b) {
    const low = Math.min(a, b) - 1;
    const high = Math.max(a, b) - 1;
    return (low * (2 * MAX_NUMBER - low - 1)) / 2 + (high - low - 1);
  }

  /** Coppia corrispondente a un indice lineare. */
  function pairAt(index) {
    let remaining = index;
    let row = 0;
    while (row < MAX_NUMBER - 1) {
      const rowLength = MAX_NUMBER - row - 1;
      if (remaining < rowLength) break;
      remaining -= rowLength;
      row += 1;
    }
    return [row + 1, row + remaining + 2];
  }

  /** Chiave compatta per una terna ordinata. */
  function tripleKey(a, b, c) {
    const sorted = [a, b, c].sort((x, y) => x - y);
    return sorted[0] * 91 * 91 + sorted[1] * 91 + sorted[2];
  }

  function decodeTriple(key) {
    const third = key % 91;
    const second = Math.floor(key / 91) % 91;
    const first = Math.floor(key / (91 * 91));
    return [first, second, third];
  }

  /** Costruisce la matrice delle co-occorrenze di coppie. */
  function buildCoOccurrence(draws, drawnPerDraw) {
    const counts = new Int32Array(PAIR_COUNT);
    for (let d = 0; d < draws.length; d += 1) {
      const numbers = draws[d].numbers;
      for (let i = 0; i < numbers.length - 1; i += 1) {
        for (let j = i + 1; j < numbers.length; j += 1) {
          counts[pairIndex(numbers[i], numbers[j])] += 1;
        }
      }
    }
    return { counts: counts, drawCount: draws.length, drawnPerDraw: drawnPerDraw };
  }

  /** Uscite congiunte attese per una coppia in caso di pura casualità. */
  function expectedPairCount(drawCount, drawnPerDraw) {
    if (drawCount <= 0 || drawnPerDraw < 2) return 0;
    const k = drawnPerDraw;
    return ((k * (k - 1)) / (MAX_NUMBER * (MAX_NUMBER - 1))) * drawCount;
  }

  function expectedTripleCount(drawCount, drawnPerDraw) {
    if (drawCount <= 0 || drawnPerDraw < 3) return 0;
    const k = drawnPerDraw;
    return ((k * (k - 1) * (k - 2)) / (MAX_NUMBER * (MAX_NUMBER - 1) * (MAX_NUMBER - 2))) * drawCount;
  }

  /** Uscite attese per un insieme di `size` numeri, in caso di pura casualità. */
  function expectedSetCount(drawCount, drawnPerDraw, size) {
    if (drawCount <= 0 || drawnPerDraw < size) return 0;
    let probability = 1;
    for (let i = 0; i < size; i += 1) {
      probability *= (drawnPerDraw - i) / (MAX_NUMBER - i);
    }
    return probability * drawCount;
  }

  function coOccurrenceCount(matrix, a, b) {
    if (a === b) return 0;
    return matrix.counts[pairIndex(a, b)];
  }

  /** Rapporto osservato/atteso per una coppia: 1,0 = perfettamente in media. */
  function coOccurrenceLift(matrix, a, b) {
    const expected = expectedPairCount(matrix.drawCount, matrix.drawnPerDraw);
    if (expected <= 0) return 0;
    return coOccurrenceCount(matrix, a, b) / expected;
  }

  /** Forza di co-occorrenza di un numero: media dei lift con tutti gli altri. */
  function coOccurrenceStrength(matrix, number) {
    const expected = expectedPairCount(matrix.drawCount, matrix.drawnPerDraw);
    if (expected <= 0) return 0;
    let total = 0;
    for (let other = 1; other <= MAX_NUMBER; other += 1) {
      if (other === number) continue;
      total += matrix.counts[pairIndex(number, other)] / expected;
    }
    return total / (MAX_NUMBER - 1);
  }

  /** I partner più ricorrenti di un numero, ordinati per conteggio. */
  function topPartners(matrix, number, limit) {
    const partners = [];
    for (let other = 1; other <= MAX_NUMBER; other += 1) {
      if (other === number) continue;
      partners.push({
        number: other,
        count: coOccurrenceCount(matrix, number, other),
        lift: coOccurrenceLift(matrix, number, other)
      });
    }
    partners.sort((a, b) => b.count - a.count);
    return partners.slice(0, limit || 5);
  }

  /**
   * Indice delle uscite di coppie e terne: quante volte sono uscite insieme
   * e in quale estrazione è avvenuta l'ultima uscita congiunta.
   */
  function buildOccurrenceIndex(draws, drawnPerDraw) {
    const pairCounts = new Int32Array(PAIR_COUNT);
    const pairLastIndex = new Int32Array(PAIR_COUNT).fill(-1);
    const triples = new Map();

    for (let d = 0; d < draws.length; d += 1) {
      const numbers = draws[d].numbers;
      for (let i = 0; i < numbers.length - 1; i += 1) {
        for (let j = i + 1; j < numbers.length; j += 1) {
          const index = pairIndex(numbers[i], numbers[j]);
          pairCounts[index] += 1;
          pairLastIndex[index] = d;
        }
      }
      for (let i = 0; i < numbers.length - 2; i += 1) {
        for (let j = i + 1; j < numbers.length - 1; j += 1) {
          for (let k = j + 1; k < numbers.length; k += 1) {
            const key = tripleKey(numbers[i], numbers[j], numbers[k]);
            const current = triples.get(key);
            if (current) {
              current.count += 1;
              current.lastIndex = d;
            } else {
              triples.set(key, { count: 1, lastIndex: d });
            }
          }
        }
      }
    }

    return {
      pairCounts: pairCounts,
      pairLastIndex: pairLastIndex,
      triples: triples,
      drawCount: draws.length,
      drawnPerDraw: drawnPerDraw,
      expectedPair: expectedPairCount(draws.length, drawnPerDraw),
      expectedTriple: expectedTripleCount(draws.length, drawnPerDraw)
    };
  }

  function indexPairCount(index, a, b) {
    if (a === b) return 0;
    return index.pairCounts[pairIndex(a, b)];
  }

  /** Estrazioni trascorse dall'ultima uscita congiunta della coppia. */
  function indexPairDelay(index, a, b) {
    if (a === b) return index.drawCount;
    const last = index.pairLastIndex[pairIndex(a, b)];
    if (last < 0) return index.drawCount;
    return index.drawCount - 1 - last;
  }

  function indexPairLift(index, a, b) {
    if (index.expectedPair <= 0) return 0;
    return indexPairCount(index, a, b) / index.expectedPair;
  }

  function indexTripleCount(index, a, b, c) {
    const entry = index.triples.get(tripleKey(a, b, c));
    return entry ? entry.count : 0;
  }

  function indexTripleDelay(index, a, b, c) {
    const entry = index.triples.get(tripleKey(a, b, c));
    if (!entry) return index.drawCount;
    return index.drawCount - 1 - entry.lastIndex;
  }

  Object.assign(Lotto, {
    MAX_NUMBER: MAX_NUMBER,
    PAIR_COUNT: PAIR_COUNT,
    pairIndex: pairIndex,
    pairAt: pairAt,
    tripleKey: tripleKey,
    decodeTriple: decodeTriple,
    buildCoOccurrence: buildCoOccurrence,
    expectedPairCount: expectedPairCount,
    expectedSetCount: expectedSetCount,
    expectedTripleCount: expectedTripleCount,
    coOccurrenceCount: coOccurrenceCount,
    coOccurrenceLift: coOccurrenceLift,
    coOccurrenceStrength: coOccurrenceStrength,
    topPartners: topPartners,
    buildOccurrenceIndex: buildOccurrenceIndex,
    indexPairCount: indexPairCount,
    indexPairDelay: indexPairDelay,
    indexPairLift: indexPairLift,
    indexTripleCount: indexTripleCount,
    indexTripleDelay: indexTripleDelay
  });
})(typeof self !== 'undefined' ? self : this);
