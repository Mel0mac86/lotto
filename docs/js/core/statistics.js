/* Motore statistico: dalle estrazioni grezze alle metriche per numero.
   Porting fedele di StatisticsEngine.swift. Nessuna dipendenza dall'interfaccia:
   può girare dentro un Web Worker. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  /** Un'estrazione normalizzata. `date` è un timestamp in millisecondi. */
  function makeDraw(date, game, wheel, numbers, jolly, superstar) {
    const sorted = numbers.slice().sort((a, b) => a - b);
    return {
      date: date,
      game: game,
      wheel: wheel || null,
      numbers: sorted,
      jolly: (jolly === undefined || jolly === null) ? null : jolly,
      superstar: (superstar === undefined || superstar === null) ? null : superstar
    };
  }

  function drawSum(draw) {
    let total = 0;
    for (let i = 0; i < draw.numbers.length; i += 1) total += draw.numbers[i];
    return total;
  }

  function evenCount(draw) {
    let count = 0;
    for (let i = 0; i < draw.numbers.length; i += 1) if (draw.numbers[i] % 2 === 0) count += 1;
    return count;
  }

  function lowCount(draw) {
    let count = 0;
    for (let i = 0; i < draw.numbers.length; i += 1) if (draw.numbers[i] <= 45) count += 1;
    return count;
  }

  function consecutivePairs(numbers) {
    let count = 0;
    for (let i = 1; i < numbers.length; i += 1) {
      if (numbers[i] === numbers[i - 1] + 1) count += 1;
    }
    return count;
  }

  /** Chiave di deduplica: gioco|ruota|data|numeri ordinati. */
  function dedupeKey(draw) {
    const day = new Date(draw.date).toISOString().slice(0, 10);
    return draw.game + '|' + (draw.wheel || '-') + '|' + day + '|' + draw.numbers.join('-');
  }

  function yearOf(draw) { return new Date(draw.date).getFullYear(); }
  function monthOf(draw) { return new Date(draw.date).getMonth() + 1; }

  /**
   * Applica il filtro a un insieme di estrazioni.
   *
   * `cutoff` è un limite STRETTO: le estrazioni con data maggiore o uguale al
   * cutoff vengono eliminate. È la barriera che impedisce il data leakage nei
   * backtest walk-forward.
   */
  function applyFilter(filter, draws) {
    let result = draws.filter((draw) => draw.game === filter.game);

    if (Lotto.GAMES[filter.game].usesWheels && filter.wheel && filter.wheel !== 'all') {
      result = result.filter((draw) => draw.wheel === filter.wheel);
    }
    if (filter.cutoff) {
      result = result.filter((draw) => draw.date < filter.cutoff);
    }
    if (filter.calendarYear) {
      result = result.filter((draw) => yearOf(draw) === filter.calendarYear);
    } else {
      const period = Lotto.periodById(filter.period || 'all');
      if (period.years) {
        const reference = filter.cutoff || (result.length ? result[result.length - 1].date : Date.now());
        const start = new Date(reference);
        start.setFullYear(start.getFullYear() - period.years);
        const startTime = start.getTime();
        result = result.filter((draw) => draw.date >= startTime);
      }
    }
    return result.slice().sort((a, b) => a.date - b.date);
  }

  /** Statistiche descrittive complete per l'insieme di estrazioni fornito. */
  function computeStatistics(draws, gameId) {
    const game = Lotto.GAMES[gameId];
    const total = draws.length;
    const stats = {
      drawCount: total,
      firstDate: total ? draws[0].date : null,
      lastDate: total ? draws[total - 1].date : null,
      numbers: {},
      sums: [],
      evenDistribution: {},
      lowDistribution: {},
      decadeDistribution: {},
      unitDistribution: {},
      drawsWithConsecutives: 0,
      byYear: {},
      byMonth: {},
      byWheel: {}
    };

    for (let number = 1; number <= 90; number += 1) {
      stats.numbers[number] = emptyNumberStats(number);
    }
    if (total === 0) return stats;

    const occurrences = new Int32Array(91);
    const lastIndex = new Int32Array(91).fill(-1);
    const lastDate = new Float64Array(91);
    const gaps = [];
    for (let i = 0; i <= 90; i += 1) gaps.push([]);

    for (let index = 0; index < total; index += 1) {
      const draw = draws[index];
      stats.sums.push(drawSum(draw));
      const even = evenCount(draw);
      const low = lowCount(draw);
      stats.evenDistribution[even] = (stats.evenDistribution[even] || 0) + 1;
      stats.lowDistribution[low] = (stats.lowDistribution[low] || 0) + 1;
      if (consecutivePairs(draw.numbers) > 0) stats.drawsWithConsecutives += 1;

      const year = yearOf(draw);
      const month = monthOf(draw);
      if (!stats.byYear[year]) stats.byYear[year] = {};
      if (!stats.byMonth[month]) stats.byMonth[month] = {};
      if (draw.wheel && !stats.byWheel[draw.wheel]) stats.byWheel[draw.wheel] = {};

      for (let n = 0; n < draw.numbers.length; n += 1) {
        const number = draw.numbers[n];
        occurrences[number] += 1;
        const decade = Math.min(Math.floor((number - 1) / 10), 8);
        stats.decadeDistribution[decade] = (stats.decadeDistribution[decade] || 0) + 1;
        const unit = number % 10;
        stats.unitDistribution[unit] = (stats.unitDistribution[unit] || 0) + 1;
        stats.byYear[year][number] = (stats.byYear[year][number] || 0) + 1;
        stats.byMonth[month][number] = (stats.byMonth[month][number] || 0) + 1;
        if (draw.wheel) {
          stats.byWheel[draw.wheel][number] = (stats.byWheel[draw.wheel][number] || 0) + 1;
        }

        if (lastIndex[number] >= 0) {
          gaps[number].push(index - lastIndex[number] - 1);
        } else {
          // Ritardo iniziale: estrazioni trascorse prima della prima uscita.
          gaps[number].push(index);
        }
        lastIndex[number] = index;
        lastDate[number] = draw.date;
      }
    }

    // Finestra "recente": ultimo quarto delle estrazioni, minimo 20 se disponibili.
    const recentWindow = Math.max(Math.min(total, 20), Math.floor(total / 4));
    const recentDraws = draws.slice(total - recentWindow);
    const recentOccurrences = new Int32Array(91);
    for (let i = 0; i < recentDraws.length; i += 1) {
      const numbers = recentDraws[i].numbers;
      for (let n = 0; n < numbers.length; n += 1) recentOccurrences[numbers[n]] += 1;
    }

    // Volatilità: frequenze su un massimo di 8 sotto-periodi di uguale ampiezza.
    const bucketCount = Math.min(8, Math.max(2, Math.floor(total / 25)));
    const bucketSize = Math.max(1, Math.floor(total / bucketCount));
    const buckets = [];
    for (let i = 0; i <= 90; i += 1) buckets.push(new Int32Array(bucketCount));
    for (let index = 0; index < total; index += 1) {
      const bucket = Math.min(Math.floor(index / bucketSize), bucketCount - 1);
      const numbers = draws[index].numbers;
      for (let n = 0; n < numbers.length; n += 1) buckets[numbers[n]][bucket] += 1;
    }

    const matrix = Lotto.buildCoOccurrence(draws, game.drawnCount);
    const expectedFrequency = game.drawnCount / 90;

    for (let number = 1; number <= 90; number += 1) {
      const item = stats.numbers[number];
      item.occurrences = occurrences[number];
      item.frequency = occurrences[number] / total;
      item.expectedFrequency = expectedFrequency;
      item.frequencyRatio = expectedFrequency > 0 ? item.frequency / expectedFrequency : 0;

      if (lastIndex[number] >= 0) {
        item.currentDelay = total - 1 - lastIndex[number];
        item.lastSeen = lastDate[number];
      } else {
        // Mai uscito nel periodo: il ritardo è pari all'intera finestra.
        item.currentDelay = total;
        item.lastSeen = null;
      }

      const allGaps = gaps[number].concat([item.currentDelay]);
      let gapSum = 0;
      let gapMax = 0;
      for (let g = 0; g < allGaps.length; g += 1) {
        gapSum += allGaps[g];
        if (allGaps[g] > gapMax) gapMax = allGaps[g];
      }
      item.averageDelay = allGaps.length ? gapSum / allGaps.length : 0;
      item.maxDelay = gapMax;
      item.delayRatio = gapMax > 0 ? item.currentDelay / gapMax : 0;

      item.recentFrequency = recentDraws.length ? recentOccurrences[number] / recentDraws.length : 0;
      if (item.frequency > 0) {
        item.trendRatio = item.recentFrequency / item.frequency;
      } else {
        item.trendRatio = item.recentFrequency > 0 ? 2 : 1;
      }

      const series = buckets[number];
      if (series.length > 1) {
        let mean = 0;
        for (let b = 0; b < series.length; b += 1) mean += series[b];
        mean /= series.length;
        if (mean > 0) {
          let variance = 0;
          for (let b = 0; b < series.length; b += 1) variance += Math.pow(series[b] - mean, 2);
          item.volatility = Math.sqrt(variance / series.length) / mean;
        } else {
          item.volatility = 1;
        }
      }

      item.coOccurrenceStrength = Lotto.coOccurrenceStrength(matrix, number);
    }

    // Percentili di frequenza, con gestione dei pari merito.
    const ordered = [];
    for (let number = 1; number <= 90; number += 1) ordered.push(stats.numbers[number]);
    ordered.sort((a, b) => a.occurrences - b.occurrences);
    const denominator = Math.max(ordered.length - 1, 1);
    for (let rank = 0; rank < ordered.length; rank += 1) {
      ordered[rank].frequencyPercentile = (rank / denominator) * 100;
    }

    return stats;
  }

  function emptyNumberStats(number) {
    return {
      number: number,
      occurrences: 0,
      frequency: 0,
      expectedFrequency: 0,
      frequencyRatio: 0,
      currentDelay: 0,
      averageDelay: 0,
      maxDelay: 0,
      delayRatio: 0,
      lastSeen: null,
      recentFrequency: 0,
      trendRatio: 1,
      volatility: 0,
      coOccurrenceStrength: 0,
      frequencyPercentile: 0
    };
  }

  function isHot(item) { return item.trendRatio >= 1.10; }
  function isCold(item) { return item.trendRatio <= 0.90; }
  function isOverdue(item) { return item.averageDelay > 0 && item.currentDelay > item.averageDelay * 1.5; }

  Object.assign(Lotto, {
    makeDraw: makeDraw,
    drawSum: drawSum,
    evenCount: evenCount,
    lowCount: lowCount,
    consecutivePairs: consecutivePairs,
    dedupeKey: dedupeKey,
    yearOf: yearOf,
    monthOf: monthOf,
    applyFilter: applyFilter,
    computeStatistics: computeStatistics,
    isHot: isHot,
    isCold: isCold,
    isOverdue: isOverdue
  });
})(typeof self !== 'undefined' ? self : this);
