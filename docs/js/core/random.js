/* Generatore pseudo-casuale deterministico (SplitMix64) e utilità di campionamento.
   Serve a rendere riproducibili backtest, simulazioni e generatori: con lo stesso
   seme l'algoritmo produce sempre le stesse combinazioni. */
(function (root) {
  'use strict';

  const MASK = 0xFFFFFFFFn;

  class SeededRandom {
    constructor(seed) {
      const value = BigInt(Math.floor(seed) || 0);
      this.state = value === 0n ? 0x9E3779B97F4A7C15n : BigInt.asUintN(64, value);
    }

    /** Prossimo intero a 64 bit come BigInt. */
    nextBig() {
      this.state = BigInt.asUintN(64, this.state + 0x9E3779B97F4A7C15n);
      let z = this.state;
      z = BigInt.asUintN(64, (z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n);
      z = BigInt.asUintN(64, (z ^ (z >> 27n)) * 0x94D049BB133111EBn);
      return z ^ (z >> 31n);
    }

    /** Double uniforme in [0, 1). */
    next() {
      return Number(this.nextBig() >> 11n) / 9007199254740992;
    }

    /** Intero uniforme in [0, bound). */
    nextInt(bound) {
      if (bound <= 0) return 0;
      return Number(this.nextBig() % BigInt(bound));
    }

    /** `count` numeri distinti estratti da 1…max senza reimmissione. */
    drawNumbers(count, max) {
      const pool = new Array(max);
      for (let i = 0; i < max; i += 1) pool[i] = i + 1;
      for (let position = 0; position < count; position += 1) {
        const swap = position + this.nextInt(max - position);
        const temp = pool[position];
        pool[position] = pool[swap];
        pool[swap] = temp;
      }
      return pool.slice(0, count).sort((a, b) => a - b);
    }

    /** Campionamento pesato senza reimmissione: restituisce gli indici scelti. */
    weightedSample(weights, count) {
      const remaining = weights.slice();
      const picked = [];
      for (let step = 0; step < count; step += 1) {
        let total = 0;
        for (let i = 0; i < remaining.length; i += 1) total += remaining[i];
        if (total <= 0) break;
        let threshold = this.next() * total;
        let chosen = remaining.length - 1;
        for (let i = 0; i < remaining.length; i += 1) {
          threshold -= remaining[i];
          if (threshold <= 0) { chosen = i; break; }
        }
        picked.push(chosen);
        remaining[chosen] = 0;
      }
      return picked;
    }
  }

  root.Lotto = root.Lotto || {};
  root.Lotto.SeededRandom = SeededRandom;
})(typeof self !== 'undefined' ? self : this);
