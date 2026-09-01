/* Modulo sperimentale di machine learning.

   IMPORTANTE: nessuno di questi modelli è capace di prevedere un'estrazione
   casuale. Servono a classificare pattern storici, raggruppare numeri, misurare
   co-occorrenze, rilevare anomalie e — soprattutto — a quantificare onestamente
   l'assenza di potere predittivo. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  const FEATURE_NAMES = ['Frequenza', 'Ritardo', 'Trend', 'Volatilità', 'Co-occorrenza', 'Recenza'];

  const ML_MODELS = [
    { id: 'logisticRegression', name: 'Regressione logistica', supervised: true,
      purpose: 'Misura quanto le feature storiche siano informative rispetto all’esito di un’estrazione.' },
    { id: 'randomForest', name: 'Random Forest', supervised: true,
      purpose: 'Insieme di alberi decisionali usato per il ranking statistico e il confronto con la baseline.' },
    { id: 'gradientBoosting', name: 'Gradient Boosting', supervised: true,
      purpose: 'Alberi additivi della famiglia XGBoost/LightGBM: il modello più capace fra quelli inclusi, ed è proprio per questo che il suo risultato è il confronto più severo con la casualità.' },
    { id: 'clustering', name: 'Clustering (k-means)', supervised: false,
      purpose: 'Raggruppa i numeri per profilo statistico (frequenza, ritardo, trend, volatilità).' },
    { id: 'bayesian', name: 'Modello bayesiano', supervised: false,
      purpose: 'Stima la probabilità a posteriori di ciascun numero e la confronta con quella teorica.' },
    { id: 'anomalyDetection', name: 'Rilevazione anomalie', supervised: false,
      purpose: 'Individua i numeri il cui profilo statistico si discosta di più dalla media.' },
    // Calcolato fuori dal telefono: vedi docs/js/data/timesfm.js.
    { id: 'timesfm', name: 'TimesFM 3.0 (Google)', supervised: true, external: true,
      purpose: 'Modello di forecasting pre-addestrato di Google Research, primo in classifica sui benchmark di serie temporali. Qui è messo alla prova sulle estrazioni: prevede i numeri della prossima estrazione, e accanto trovi la misura di quanto quella previsione valga.' }
  ];

  function normalizeColumn(values) {
    let min = Infinity;
    let max = -Infinity;
    values.forEach((value) => { if (value < min) min = value; if (value > max) max = value; });
    if (!(max > min)) return values.map(() => 0.5);
    return values.map((value) => (value - min) / (max - min));
  }

  /** Feature per numero, normalizzate 0–1. */
  function numberFeatures(context) {
    const items = [];
    for (let n = 1; n <= 90; n += 1) items.push(context.statistics.numbers[n]);
    const frequency = normalizeColumn(items.map((item) => item.occurrences));
    const delay = normalizeColumn(items.map((item) => item.currentDelay));
    const volatility = normalizeColumn(items.map((item) => item.volatility));
    const coOccurrence = normalizeColumn(items.map((item) => item.coOccurrenceStrength));

    return items.map((item, index) => ({
      number: item.number,
      vector: [
        frequency[index],
        delay[index],
        Lotto.trendScore(item.trendRatio) / 100,
        volatility[index],
        coOccurrence[index],
        1 - Math.min(item.currentDelay / Math.max(item.maxDelay, 1), 1)
      ]
    }));
  }

  /**
   * Dataset supervisionato walk-forward: per ogni estrazione e per ogni numero,
   * le feature calcolate SOLO sulle estrazioni precedenti e l'etichetta
   * "il numero è uscito in questa estrazione".
   */
  function supervisedDataset(draws, gameId, warmup, stride) {
    const start = warmup || 200;
    const step = stride || 5;
    if (draws.length <= start + 10) return { features: [], labels: [] };
    const features = [];
    const labels = [];

    for (let index = start; index < draws.length; index += step) {
      const history = draws.slice(0, index);
      const statistics = Lotto.computeStatistics(history, gameId);
      const target = new Set(draws[index].numbers);
      for (let number = 1; number <= 90; number += 1) {
        const item = statistics.numbers[number];
        features.push([
          item.frequency * 90,
          item.currentDelay / 100,
          Lotto.trendScore(item.trendRatio) / 100,
          item.volatility,
          item.coOccurrenceStrength,
          item.maxDelay / 100
        ]);
        labels.push(target.has(number) ? 1 : 0);
      }
    }
    return { features: features, labels: labels };
  }

  // ------------------------------------------------- Regressione logistica

  function trainLogisticRegression(features, labels, epochs, learningRate, l2) {
    const width = features[0].length;
    const weights = new Array(width).fill(0);
    let bias = 0;
    const sampleCount = features.length;
    const rounds = epochs || 120;
    const rate = learningRate === undefined ? 0.15 : learningRate;
    const penalty = l2 === undefined ? 0.001 : l2;

    for (let epoch = 0; epoch < rounds; epoch += 1) {
      const gradients = new Array(width).fill(0);
      let biasGradient = 0;
      for (let i = 0; i < sampleCount; i += 1) {
        const feature = features[i];
        let z = bias;
        for (let d = 0; d < width; d += 1) z += weights[d] * feature[d];
        const error = 1 / (1 + Math.exp(-z)) - labels[i];
        for (let d = 0; d < width; d += 1) gradients[d] += error * feature[d];
        biasGradient += error;
      }
      for (let d = 0; d < width; d += 1) {
        weights[d] -= rate * (gradients[d] / sampleCount + penalty * weights[d]);
      }
      bias -= rate * (biasGradient / sampleCount);
    }

    return {
      weights: weights,
      bias: bias,
      predict: function (feature) {
        let z = bias;
        for (let d = 0; d < Math.min(width, feature.length); d += 1) z += weights[d] * feature[d];
        return 1 / (1 + Math.exp(-z));
      }
    };
  }

  // ---------------------------------------------------- Alberi decisionali

  /** Soglie candidate stimate su un campione: ordinare tutti i valori a ogni
      nodo domina il costo dell'addestramento. */
  function sampledQuantiles(indices, features, feature, fractions) {
    const step = Math.max(1, Math.floor(indices.length / 512));
    const values = [];
    for (let position = 0; position < indices.length; position += step) {
      values.push(features[indices[position]][feature]);
    }
    values.sort((a, b) => a - b);
    if (!values.length || values[values.length - 1] <= values[0]) return null;
    const thresholds = [];
    fractions.forEach((fraction) => {
      const candidate = values[Math.floor((values.length - 1) * fraction)];
      if (candidate < values[values.length - 1] && thresholds.indexOf(candidate) < 0) {
        thresholds.push(candidate);
      }
    });
    return thresholds;
  }

  function buildClassificationTree(indices, features, labels, depth, maxDepth, minSamples, subset) {
    let positives = 0;
    indices.forEach((i) => { positives += labels[i]; });
    const probability = indices.length ? positives / indices.length : 0.5;
    if (depth >= maxDepth || indices.length < minSamples || positives === 0 || positives === indices.length) {
      return { leaf: true, value: probability };
    }
    const gini = (p) => 2 * p * (1 - p);
    const parent = gini(probability);
    let best = null;

    subset.forEach((feature) => {
      const thresholds = sampledQuantiles(indices, features, feature, [0.25, 0.5, 0.75]);
      if (!thresholds) return;
      thresholds.forEach((threshold) => {
        const left = [];
        const right = [];
        indices.forEach((i) => { (features[i][feature] <= threshold ? left : right).push(i); });
        if (left.length < minSamples / 2 || right.length < minSamples / 2) return;
        let leftPositives = 0;
        left.forEach((i) => { leftPositives += labels[i]; });
        let rightPositives = 0;
        right.forEach((i) => { rightPositives += labels[i]; });
        const weighted = (left.length * gini(leftPositives / left.length)
          + right.length * gini(rightPositives / right.length)) / indices.length;
        const gain = parent - weighted;
        if (!best || gain > best.gain) best = { feature: feature, threshold: threshold, gain: gain, left: left, right: right };
      });
    });

    if (!best || best.gain <= 1e-9) return { leaf: true, value: probability };
    return {
      leaf: false,
      feature: best.feature,
      threshold: best.threshold,
      left: buildClassificationTree(best.left, features, labels, depth + 1, maxDepth, minSamples, subset),
      right: buildClassificationTree(best.right, features, labels, depth + 1, maxDepth, minSamples, subset)
    };
  }

  function predictTree(node, feature) {
    let current = node;
    while (!current.leaf) {
      current = feature[current.feature] <= current.threshold ? current.left : current.right;
    }
    return current.value;
  }

  /** Random Forest: alberi su campioni bootstrap e sottoinsiemi di feature. */
  function trainRandomForest(features, labels, treeCount, maxDepth, seed) {
    const generator = new Lotto.SeededRandom(seed || 3);
    const width = features[0].length;
    const subsetSize = Math.max(2, Math.round(Math.sqrt(width)));
    const trees = [];

    for (let t = 0; t < (treeCount || 20); t += 1) {
      const bootstrapFeatures = [];
      const bootstrapLabels = [];
      for (let i = 0; i < features.length; i += 1) {
        const index = generator.nextInt(features.length);
        bootstrapFeatures.push(features[index]);
        bootstrapLabels.push(labels[index]);
      }
      const available = [];
      for (let d = 0; d < width; d += 1) available.push(d);
      const subset = [];
      for (let s = 0; s < subsetSize && available.length; s += 1) {
        subset.push(available.splice(generator.nextInt(available.length), 1)[0]);
      }
      const indices = [];
      for (let i = 0; i < bootstrapFeatures.length; i += 1) indices.push(i);
      trees.push(buildClassificationTree(indices, bootstrapFeatures, bootstrapLabels, 0,
        maxDepth || 5, 25, subset));
    }

    return {
      predict: function (feature) {
        if (!trees.length) return 0.5;
        let total = 0;
        trees.forEach((tree) => { total += predictTree(tree, feature); });
        return total / trees.length;
      }
    };
  }

  // ------------------------------------------------------ Gradient boosting

  /**
   * Alberi di regressione additivi con perdita logistica: la stessa famiglia di
   * XGBoost e LightGBM, che non esistono come librerie in un browser. Le foglie
   * usano il passo di Newton di Friedman, G / (H + lambda).
   */
  function buildRegressionTree(indices, features, gradients, hessians, depth, maxDepth, minSamples, subset, lambda) {
    const leafValue = (list) => {
      if (!list.length) return 0;
      let g = 0;
      let h = 0;
      list.forEach((i) => { g += gradients[i]; h += hessians[i]; });
      return g / (h + lambda);
    };
    const structureGain = (list) => {
      if (!list.length) return 0;
      let g = 0;
      let h = 0;
      list.forEach((i) => { g += gradients[i]; h += hessians[i]; });
      return (g * g) / (h + lambda);
    };

    const value = leafValue(indices);
    if (depth >= maxDepth || indices.length < minSamples * 2) return { leaf: true, value: value };

    const parent = structureGain(indices);
    let best = null;
    subset.forEach((feature) => {
      const thresholds = sampledQuantiles(indices, features, feature, [0.2, 0.4, 0.6, 0.8]);
      if (!thresholds) return;
      thresholds.forEach((threshold) => {
        const left = [];
        const right = [];
        indices.forEach((i) => { (features[i][feature] <= threshold ? left : right).push(i); });
        if (left.length < minSamples || right.length < minSamples) return;
        const improvement = structureGain(left) + structureGain(right) - parent;
        if (!best || improvement > best.improvement) {
          best = { feature: feature, threshold: threshold, improvement: improvement, left: left, right: right };
        }
      });
    });

    if (!best || best.improvement <= 1e-9) return { leaf: true, value: value };
    return {
      leaf: false,
      feature: best.feature,
      threshold: best.threshold,
      left: buildRegressionTree(best.left, features, gradients, hessians, depth + 1, maxDepth, minSamples, subset, lambda),
      right: buildRegressionTree(best.right, features, gradients, hessians, depth + 1, maxDepth, minSamples, subset, lambda)
    };
  }

  function trainGradientBoosting(features, labels, options) {
    const settings = Object.assign({
      treeCount: 40, maxDepth: 3, learningRate: 0.15, subsample: 0.8, colsample: 0.8, lambda: 1, seed: 11
    }, options || {});
    const generator = new Lotto.SeededRandom(settings.seed);
    const width = features[0].length;
    const trees = [];

    let positives = 0;
    labels.forEach((label) => { positives += label; });
    const rate = Math.min(Math.max(positives / labels.length, 1e-6), 1 - 1e-6);
    const initialScore = Math.log(rate / (1 - rate));
    const scores = new Float64Array(features.length).fill(initialScore);
    const columnCount = Math.max(1, Math.round(width * settings.colsample));

    for (let round = 0; round < settings.treeCount; round += 1) {
      const gradients = new Float64Array(features.length);
      const hessians = new Float64Array(features.length);
      for (let i = 0; i < features.length; i += 1) {
        const probability = 1 / (1 + Math.exp(-scores[i]));
        gradients[i] = labels[i] - probability;
        hessians[i] = Math.max(probability * (1 - probability), 1e-6);
      }

      const rows = [];
      for (let i = 0; i < features.length; i += 1) {
        if (generator.next() < settings.subsample) rows.push(i);
      }
      if (rows.length <= 40) continue;

      const available = [];
      for (let d = 0; d < width; d += 1) available.push(d);
      const subset = [];
      for (let s = 0; s < columnCount && available.length; s += 1) {
        subset.push(available.splice(generator.nextInt(available.length), 1)[0]);
      }

      const tree = buildRegressionTree(rows, features, gradients, hessians, 0, settings.maxDepth,
        Math.max(20, Math.floor(rows.length / 100)), subset, settings.lambda);
      trees.push(tree);
      for (let i = 0; i < features.length; i += 1) {
        scores[i] += settings.learningRate * predictTree(tree, features[i]);
      }
    }

    return {
      treeCount: trees.length,
      predict: function (feature) {
        let score = initialScore;
        trees.forEach((tree) => { score += settings.learningRate * predictTree(tree, feature); });
        return 1 / (1 + Math.exp(-score));
      }
    };
  }

  // ------------------------------------------------------------- Metriche

  /** Area sotto la curva ROC, con la statistica di Mann–Whitney. */
  function areaUnderROC(probabilities, labels) {
    const combined = [];
    let positives = 0;
    let negatives = 0;
    for (let i = 0; i < probabilities.length; i += 1) {
      combined.push({ value: probabilities[i], label: labels[i] });
      if (labels[i] === 1) positives += 1; else negatives += 1;
    }
    if (!positives || !negatives) return 0.5;
    combined.sort((a, b) => a.value - b.value);

    const ranks = new Array(combined.length);
    let index = 0;
    while (index < combined.length) {
      let end = index;
      while (end + 1 < combined.length && combined[end + 1].value === combined[index].value) end += 1;
      const averageRank = (index + end) / 2 + 1;
      for (let position = index; position <= end; position += 1) ranks[position] = averageRank;
      index = end + 1;
    }
    let positiveRankSum = 0;
    for (let position = 0; position < combined.length; position += 1) {
      if (combined[position].label === 1) positiveRankSum += ranks[position];
    }
    return (positiveRankSum - (positives * (positives + 1)) / 2) / (positives * negatives);
  }

  function logLoss(probabilities, labels) {
    if (!probabilities.length) return 0;
    let total = 0;
    for (let i = 0; i < probabilities.length; i += 1) {
      const clamped = Math.min(Math.max(probabilities[i], 1e-9), 1 - 1e-9);
      total += labels[i] === 1 ? -Math.log(clamped) : -Math.log(1 - clamped);
    }
    return total / probabilities.length;
  }

  // ------------------------------------------------------- K-means e altro

  function kMeans(points, k, seed, iterations) {
    if (!points.length || k <= 0) return { centroids: [], assignments: [] };
    const clusters = Math.min(k, points.length);
    const generator = new Lotto.SeededRandom(seed || 1);
    const distance = (a, b) => {
      let total = 0;
      for (let i = 0; i < Math.min(a.length, b.length); i += 1) total += Math.pow(a[i] - b[i], 2);
      return total;
    };

    // Inizializzazione k-means++ deterministica.
    const centroids = [points[generator.nextInt(points.length)].slice()];
    while (centroids.length < clusters) {
      const distances = points.map((point) => {
        let best = Infinity;
        centroids.forEach((centroid) => { best = Math.min(best, distance(point, centroid)); });
        return best;
      });
      let total = 0;
      distances.forEach((value) => { total += value; });
      if (total <= 0) { centroids.push(points[generator.nextInt(points.length)].slice()); continue; }
      let threshold = generator.next() * total;
      let chosen = points.length - 1;
      for (let i = 0; i < distances.length; i += 1) {
        threshold -= distances[i];
        if (threshold <= 0) { chosen = i; break; }
      }
      centroids.push(points[chosen].slice());
    }

    const assignments = new Array(points.length).fill(0);
    const rounds = iterations || 60;
    for (let round = 0; round < rounds; round += 1) {
      let changed = false;
      for (let i = 0; i < points.length; i += 1) {
        let bestCluster = 0;
        let bestDistance = Infinity;
        for (let c = 0; c < centroids.length; c += 1) {
          const d = distance(points[i], centroids[c]);
          if (d < bestDistance) { bestDistance = d; bestCluster = c; }
        }
        if (assignments[i] !== bestCluster) { assignments[i] = bestCluster; changed = true; }
      }
      const sums = centroids.map(() => new Array(points[0].length).fill(0));
      const counts = new Array(centroids.length).fill(0);
      for (let i = 0; i < points.length; i += 1) {
        const cluster = assignments[i];
        counts[cluster] += 1;
        for (let d = 0; d < points[i].length; d += 1) sums[cluster][d] += points[i][d];
      }
      for (let c = 0; c < centroids.length; c += 1) {
        if (counts[c] > 0) centroids[c] = sums[c].map((value) => value / counts[c]);
      }
      if (!changed) break;
    }
    return { centroids: centroids, assignments: assignments };
  }

  function describeCentroid(centroid) {
    if (!centroid || centroid.length < 4) return 'Profilo non disponibile.';
    const level = (value) => (value < 0.34 ? 'bassa' : (value < 0.67 ? 'media' : 'alta'));
    return 'Frequenza ' + level(centroid[0]) + ', ritardo ' + level(centroid[1])
      + ', trend ' + level(centroid[2]) + ', volatilità ' + level(centroid[3]) + '.';
  }

  function clusterNumbers(context, k) {
    const features = numberFeatures(context);
    const clusters = k || 4;
    if (features.length < clusters) return [];
    const result = kMeans(features.map((item) => item.vector), clusters, 17);
    const grouped = {};
    result.assignments.forEach((cluster, index) => {
      if (!grouped[cluster]) grouped[cluster] = [];
      grouped[cluster].push(features[index].number);
    });
    return Object.keys(grouped).sort((a, b) => a - b).map((key) => ({
      index: Number(key),
      title: 'Gruppo ' + (Number(key) + 1),
      numbers: grouped[key].sort((a, b) => a - b),
      profile: describeCentroid(result.centroids[Number(key)])
    }));
  }

  /** Numeri con profilo statistico più distante dalla media. */
  function anomalies(context, limit) {
    const features = numberFeatures(context);
    if (!features.length) return [];
    const dimensions = features[0].vector.length;
    const means = new Array(dimensions).fill(0);
    features.forEach((item) => {
      for (let d = 0; d < dimensions; d += 1) means[d] += item.vector[d];
    });
    for (let d = 0; d < dimensions; d += 1) means[d] /= features.length;

    const deviations = new Array(dimensions).fill(0);
    features.forEach((item) => {
      for (let d = 0; d < dimensions; d += 1) deviations[d] += Math.pow(item.vector[d] - means[d], 2);
    });
    for (let d = 0; d < dimensions; d += 1) {
      deviations[d] = Math.max(Math.sqrt(deviations[d] / features.length), 1e-6);
    }

    const scored = features.map((item) => {
      let distance = 0;
      let strongest = { name: '', value: 0 };
      for (let d = 0; d < dimensions; d += 1) {
        const z = (item.vector[d] - means[d]) / deviations[d];
        distance += z * z;
        if (Math.abs(z) > Math.abs(strongest.value)) strongest = { name: FEATURE_NAMES[d], value: z };
      }
      return {
        number: item.number,
        distance: Math.sqrt(distance),
        explanation: 'Scostamento maggiore su «' + strongest.name + '»: '
          + Lotto.fmt(Math.abs(strongest.value)) + ' deviazioni standard '
          + (strongest.value > 0 ? 'sopra' : 'sotto') + ' la media.'
      };
    });
    scored.sort((a, b) => b.distance - a.distance);
    return scored.slice(0, limit || 10);
  }

  /**
   * Stima bayesiana: prior Beta centrato sul valore teorico k/90, aggiornato con
   * le uscite osservate. Il risultato tipico è un posteriore molto vicino al prior:
   * è la dimostrazione quantitativa che lo storico non sposta la probabilità.
   */
  function bayesianPosteriors(context, priorStrength) {
    const trials = context.drawCount;
    if (trials === 0) return [];
    const strength = priorStrength || 200;
    const theoretical = context.gameInfo.drawnCount / 90;
    const alphaPrior = theoretical * strength;
    const betaPrior = (1 - theoretical) * strength;
    const posteriors = [];

    for (let number = 1; number <= 90; number += 1) {
      const successes = context.statistics.numbers[number].occurrences;
      const alpha = alphaPrior + successes;
      const beta = betaPrior + (trials - successes);
      const mean = alpha / (alpha + beta);
      const variance = (alpha * beta) / (Math.pow(alpha + beta, 2) * (alpha + beta + 1));
      const sigma = Math.sqrt(variance);
      const lower = Math.max(mean - 1.96 * sigma, 0);
      const upper = Math.min(mean + 1.96 * sigma, 1);
      posteriors.push({
        number: number,
        mean: mean,
        lowerBound: lower,
        upperBound: upper,
        theoretical: theoretical,
        containsTheoretical: theoretical >= lower && theoretical <= upper,
        deviationPercent: theoretical > 0 ? ((mean - theoretical) / theoretical) * 100 : 0
      });
    }
    return posteriors;
  }

  function bayesianSummary(posteriors) {
    if (!posteriors.length) return 'Dati insufficienti.';
    const outside = posteriors.filter((item) => !item.containsTheoretical);
    const expectedOutside = posteriors.length * 0.05;
    if (!outside.length) {
      return 'Per tutti i 90 numeri l’intervallo di credibilità al 95% contiene la probabilità teorica: i dati storici sono pienamente compatibili con l’equiprobabilità.';
    }
    const list = outside.slice(0, 6).map((item) => Lotto.pad(item.number)).join(', ');
    return outside.length + ' numeri su ' + posteriors.length
      + ' hanno un intervallo di credibilità che non contiene la probabilità teorica (' + list
      + '). Con intervalli al 95%, per puro caso ce ne si attendono circa ' + Lotto.fmt(expectedOutside)
      + ': il risultato è '
      + (outside.length <= expectedOutside * 2 ? 'compatibile con la casualità' : 'superiore all’atteso, ma resta una descrizione del passato') + '.';
  }

  /**
   * Addestra e valuta un modello supervisionato con split TEMPORALE 70/30:
   * nessun dato futuro entra nell'addestramento.
   */
  function evaluateModel(modelId, draws, gameId, onProgress) {
    const model = ML_MODELS.find((item) => item.id === modelId);
    if (!model || !model.supervised) return null;
    if (onProgress) onProgress(0.05);

    const dataset = supervisedDataset(draws, gameId);
    if (dataset.features.length <= 500) return null;
    if (onProgress) onProgress(0.4);

    const splitIndex = Math.floor(dataset.features.length * 0.7);
    const trainFeatures = dataset.features.slice(0, splitIndex);
    const trainLabels = dataset.labels.slice(0, splitIndex);
    const testFeatures = dataset.features.slice(splitIndex);
    const testLabels = dataset.labels.slice(splitIndex);
    if (!testFeatures.length) return null;

    let predictor;
    if (modelId === 'randomForest') {
      predictor = trainRandomForest(trainFeatures, trainLabels, 20, 5);
    } else if (modelId === 'gradientBoosting') {
      predictor = trainGradientBoosting(trainFeatures, trainLabels);
    } else {
      predictor = trainLogisticRegression(trainFeatures, trainLabels);
    }
    if (onProgress) onProgress(0.85);

    const probabilities = testFeatures.map((feature) => predictor.predict(feature));
    let positives = 0;
    trainLabels.forEach((label) => { positives += label; });
    const positiveRate = positives / trainLabels.length;

    let correct = 0;
    for (let i = 0; i < probabilities.length; i += 1) {
      if ((probabilities[i] >= 0.5 ? 1 : 0) === testLabels[i]) correct += 1;
    }
    const accuracy = correct / testLabels.length;

    // Baseline: predice sempre la classe maggioritaria (quasi sempre "non esce").
    const majority = positiveRate >= 0.5 ? 1 : 0;
    let baselineCorrect = 0;
    testLabels.forEach((label) => { if (label === majority) baselineCorrect += 1; });
    const baselineAccuracy = baselineCorrect / testLabels.length;

    const significance = Lotto.twoProportionZTest(correct, testLabels.length,
      baselineCorrect, testLabels.length, model.name + ' contro baseline');
    const auc = areaUnderROC(probabilities, testLabels);

    let verdict;
    if (auc <= 0.53 && !significance.isSignificant) {
      verdict = Lotto.DISCLAIMER.noEdge + ' L’AUC è ' + auc.toFixed(3).replace('.', ',')
        + ', praticamente indistinguibile dal valore 0,500 di un classificatore casuale.';
    } else if (significance.isSignificant) {
      verdict = 'Il modello mostra una differenza statisticamente significativa rispetto alla baseline sul campione di test (AUC '
        + auc.toFixed(3).replace('.', ',')
        + '). Su un processo casuale un risultato del genere è quasi sempre effetto della variabilità campionaria o di uno sbilanciamento delle classi: non va interpretato come capacità predittiva.';
    } else {
      verdict = Lotto.DISCLAIMER.noEdge + ' Le differenze rispetto alla baseline rientrano nella normale variabilità campionaria.';
    }

    if (onProgress) onProgress(1);
    return {
      modelName: model.name,
      trainingSamples: trainFeatures.length,
      testSamples: testFeatures.length,
      accuracy: accuracy,
      baselineAccuracy: baselineAccuracy,
      auc: auc,
      logLoss: logLoss(probabilities, testLabels),
      baselineLogLoss: logLoss(new Array(testLabels.length).fill(positiveRate), testLabels),
      significance: significance,
      verdict: verdict
    };
  }

  Object.assign(Lotto, {
    ML_MODELS: ML_MODELS,
    FEATURE_NAMES: FEATURE_NAMES,
    numberFeatures: numberFeatures,
    supervisedDataset: supervisedDataset,
    trainLogisticRegression: trainLogisticRegression,
    trainRandomForest: trainRandomForest,
    trainGradientBoosting: trainGradientBoosting,
    areaUnderROC: areaUnderROC,
    logLoss: logLoss,
    kMeans: kMeans,
    clusterNumbers: clusterNumbers,
    anomalies: anomalies,
    bayesianPosteriors: bayesianPosteriors,
    bayesianSummary: bayesianSummary,
    evaluateModel: evaluateModel
  });
})(typeof self !== 'undefined' ? self : this);
