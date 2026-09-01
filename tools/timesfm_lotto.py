#!/usr/bin/env python3
"""TimesFM 3.0 messo alla prova sulle estrazioni del Lotto.

    python3 tools/timesfm_lotto.py --steps 150 --wheel BA

Domanda a cui risponde: un modello di forecasting pre-addestrato allo stato
dell'arte riesce a prevedere quali numeri usciranno?

Metodo — walk-forward stretto. Per prevedere l'estrazione al passo t il modello
vede soltanto le estrazioni precedenti a t: il contesto è costruito da
`draws[t - CONTEXT : t]`, mai da t in poi. È la stessa barriera anti-leakage del
backtest dell'app.

Le estrazioni vengono date al modello in tre codifiche diverse, per non
penalizzarlo con una rappresentazione infelice:

- `binaria`   una serie 0/1 per numero: 1 quando il numero è uscito;
- `ritardo`   quante estrazioni sono passate dall'ultima uscita del numero;
- `frequenza` quante volte il numero è uscito nelle ultime 30 estrazioni.

TimesFM 3.0 riceve tutte e 90 le serie insieme (modalità multivariata, con
attenzione fra le variate) e prevede il passo successivo. I 90 valori previsti
diventano un punteggio: si prendono i 5 numeri col punteggio più alto e si
contano quanti erano davvero nell'estrazione.

Confronti:

- baseline casuale: 5 numeri estratti a caso, con seme fisso;
- baseline di frequenza: i 5 più frequenti nel contesto;
- controllo positivo: le stesse identiche procedure su estrazioni SINTETICHE
  costruite per essere prevedibili (periodo 10). Serve a distinguere «il
  modello non trova nulla» da «la procedura è rotta»: se il controllo non
  viene previsto bene, il risultato negativo sui dati veri non significa nulla.

Attesa teorica scegliendo 5 numeri su 90 quando ne escono 5:
media 5 x 5/90 = 0,2778 centri per estrazione, varianza ipergeometrica 0,2506.
"""
import argparse
import collections
import json
import math
import os
import random
import sys
import time

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "docs", "data", "lotto-storico.csv")

NUMBERS = 90
DRAWN = 5
FREQ_WINDOW = 30

# Media e varianza dei centri sotto ipotesi di indipendenza (ipergeometrica).
EXPECTED_HITS = DRAWN * DRAWN / NUMBERS
HITS_VARIANCE = (DRAWN * (DRAWN / NUMBERS) * (1 - DRAWN / NUMBERS)
                 * (NUMBERS - DRAWN) / (NUMBERS - 1))


# --------------------------------------------------------------------- dati

def load_wheel(code, since=None, until=None):
  draws = []
  with open(CSV, encoding="utf-8") as handle:
    next(handle)
    for line in handle:
      parts = line.rstrip("\n").split(";")
      if parts[1] != code:
        continue
      if since and parts[0] < since:
        continue
      if until and parts[0] >= until:
        continue
      draws.append((parts[0], [int(v) for v in parts[2:7]]))
  draws.sort(key=lambda row: row[0])
  return draws


def uniform_draws(count, seed=99):
  """Estrazioni FINTE e perfettamente casuali, senza alcuna struttura.

  Serve come controllo NEGATIVO: dà il vero livello di rumore delle metriche.
  Serve soprattutto alla correlazione col valore del numero, il cui z nominale
  è gonfiato perché finestre consecutive da centinaia di estrazioni si
  sovrappongono quasi del tutto, e quindi i passi non sono indipendenti."""
  rng = random.Random(seed)
  return [("%08d" % t, rng.sample(range(1, NUMBERS + 1), DRAWN)) for t in range(count)]


def synthetic_draws(count, seed=11):
  """Estrazioni FINTE ma prevedibili: periodo 10, con poco rumore.

  Serve solo come controllo positivo della procedura."""
  rng = random.Random(seed)
  base = [rng.sample(range(1, NUMBERS + 1), DRAWN) for _ in range(10)]
  draws = []
  for t in range(count):
    numbers = list(base[t % 10])
    if rng.random() < 0.1:  # un numero sostituito ogni tanto
      numbers[rng.randrange(DRAWN)] = rng.randint(1, NUMBERS)
      numbers = list(dict.fromkeys(numbers))
      while len(numbers) < DRAWN:
        candidate = rng.randint(1, NUMBERS)
        if candidate not in numbers:
          numbers.append(candidate)
    draws.append(("%08d" % t, numbers))
  return draws


# ------------------------------------------------------------- codifiche

def build_matrices(draws):
  """Le tre codifiche, ciascuna (passi, 90). Riga t = stato DOPO l'estrazione t."""
  steps = len(draws)
  binary = np.zeros((steps, NUMBERS), dtype=np.float32)
  for t, (_, numbers) in enumerate(draws):
    for n in numbers:
      binary[t, n - 1] = 1.0

  delay = np.zeros((steps, NUMBERS), dtype=np.float32)
  last = np.full(NUMBERS, -1, dtype=np.int64)
  for t in range(steps):
    for n in range(NUMBERS):
      if binary[t, n] > 0:
        last[n] = t
    delay[t] = np.where(last >= 0, t - last, t + 1)

  frequency = np.zeros((steps, NUMBERS), dtype=np.float32)
  running = np.zeros(NUMBERS, dtype=np.float32)
  for t in range(steps):
    running += binary[t]
    if t >= FREQ_WINDOW:
      running -= binary[t - FREQ_WINDOW]
    frequency[t] = running

  return {"binaria": binary, "ritardo": delay, "frequenza": frequency}


# La codifica «ritardo» va letta al contrario: un ritardo previsto basso
# significa che il modello si aspetta il numero in uscita.
SIGN = {"binaria": 1.0, "ritardo": -1.0, "frequenza": 1.0}


# ------------------------------------------------------------- valutazione

def area_under_roc(scores, labels):
  order = sorted(range(len(scores)), key=lambda i: scores[i])
  ranks = [0.0] * len(scores)
  i = 0
  while i < len(order):
    j = i
    while j + 1 < len(order) and scores[order[j + 1]] == scores[order[i]]:
      j += 1
    average = (i + j) / 2.0 + 1.0
    for k in range(i, j + 1):
      ranks[order[k]] = average
    i = j + 1
  positives = sum(labels)
  negatives = len(labels) - positives
  if positives == 0 or negatives == 0:
    return float("nan")
  rank_sum = sum(ranks[i] for i in range(len(labels)) if labels[i])
  return (rank_sum - positives * (positives + 1) / 2.0) / (positives * negatives)


def spearman_with_number(scores):
  """Correlazione fra il punteggio previsto e il valore del numero (1..90).

  È la domanda «il modello ha capito che i numeri alti escono di più?», ed è
  molto più sensibile del conteggio dei centri: usa tutti e 90 i punteggi di
  ogni estrazione invece dei soli 5 scelti."""
  order = sorted(range(NUMBERS), key=lambda n: scores[n])
  rank = [0.0] * NUMBERS
  for position, n in enumerate(order):
    rank[n] = position + 1.0
  values = [n + 1.0 for n in range(NUMBERS)]
  mean_rank = sum(rank) / NUMBERS
  mean_value = sum(values) / NUMBERS
  numerator = sum((rank[n] - mean_rank) * (values[n] - mean_value) for n in range(NUMBERS))
  denominator = math.sqrt(
    sum((rank[n] - mean_rank) ** 2 for n in range(NUMBERS))
    * sum((values[n] - mean_value) ** 2 for n in range(NUMBERS)))
  return numerator / denominator if denominator else 0.0


def summarize(name, hits, steps, auc, correlations=None):
  expected = EXPECTED_HITS * steps
  sigma = math.sqrt(HITS_VARIANCE * steps)
  z = (hits - expected) / sigma if sigma > 0 else 0.0
  p = math.erfc(abs(z) / math.sqrt(2))  # bilaterale
  entry = {
    "nome": name,
    "estrazioni": steps,
    "centri": hits,
    "centriAttesi": round(expected, 2),
    "centriPerEstrazione": round(hits / steps, 4) if steps else 0.0,
    "z": round(z, 3),
    "p": round(p, 4),
    "auc": None if auc is None or math.isnan(auc) else round(auc, 4),
    "significativo": bool(p < 0.05 and z > 0),
  }
  if correlations:
    mean = sum(correlations) / len(correlations)
    variance = sum((c - mean) ** 2 for c in correlations) / max(len(correlations) - 1, 1)
    error = math.sqrt(variance / len(correlations))
    entry["correlazioneConIlValore"] = round(mean, 4)
    entry["zCorrelazione"] = round(mean / error, 2) if error > 0 else 0.0
  return entry


# ------------------------------------------------------------------ prova

def run(draws, label, forecaster, steps, context, verbose=True):
  matrices = build_matrices(draws)
  total = len(draws)
  start = total - steps
  if start < context:
    raise SystemExit("storico insufficiente: servono almeno %d estrazioni"
                     % (context + steps))

  hits = collections.Counter()
  pooled = {key: {"scores": [], "labels": []} for key in matrices}
  correlations = collections.defaultdict(list)
  rng = random.Random(4242)
  began = time.time()

  for offset, t in enumerate(range(start, total)):
    truth = set(draws[t][1])
    labels = [1 if n + 1 in truth else 0 for n in range(NUMBERS)]

    contexts, keys = [], []
    for key, matrix in matrices.items():
      # BARRIERA: solo le estrazioni precedenti a t.
      window = matrix[t - context:t].T.astype(np.float32)
      contexts.append(np.ascontiguousarray(window))
      keys.append(key)

    outputs = list(forecaster.predict_batch(
      contexts, horizon=1, return_quantiles=False,
      use_symmetric_averaging=False, make_positive=False))

    for key, output in zip(keys, outputs):
      scores = (np.asarray(output.forecast).reshape(NUMBERS) * SIGN[key]).tolist()
      picks = sorted(range(NUMBERS), key=lambda n: scores[n], reverse=True)[:DRAWN]
      hits["timesfm/" + key] += sum(1 for n in picks if labels[n])
      pooled[key]["scores"].extend(scores)
      pooled[key]["labels"].extend(labels)
      correlations[key].append(spearman_with_number(scores))

    # Baseline: 5 a caso, e i 5 più frequenti nel contesto.
    hits["casuale"] += sum(1 for n in rng.sample(range(NUMBERS), DRAWN) if labels[n])
    counts = matrices["binaria"][t - context:t].sum(axis=0)
    top = sorted(range(NUMBERS), key=lambda n: counts[n], reverse=True)[:DRAWN]
    hits["frequenza storica"] += sum(1 for n in top if labels[n])

    if verbose and (offset + 1) % 10 == 0:
      speed = (time.time() - began) / (offset + 1)
      print("  %s  %d/%d  (%.1f s per estrazione)"
            % (label, offset + 1, steps, speed), flush=True)

  results = []
  for key in matrices:
    results.append(summarize("TimesFM 3.0 · codifica %s" % key,
                             hits["timesfm/" + key], steps,
                             area_under_roc(pooled[key]["scores"], pooled[key]["labels"]),
                             correlations[key]))
  results.append(summarize("Baseline: 5 numeri a caso", hits["casuale"], steps, None))
  results.append(summarize("Baseline: i 5 più frequenti", hits["frequenza storica"], steps, None))
  return results


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--steps", type=int, default=150)
  parser.add_argument("--context", type=int, default=512)
  parser.add_argument("--wheel", default="BA")
  parser.add_argument("--from", dest="since", default=None,
                      help="considera solo le estrazioni da questa data (aaaammgg)")
  parser.add_argument("--until", default=None,
                      help="considera solo le estrazioni prima di questa data (aaaammgg)")
  parser.add_argument("--skip-control", action="store_true")
  parser.add_argument("--solo-controllo-negativo", action="store_true",
                      help="solo il controllo su estrazioni casuali, per misurare il rumore")
  parser.add_argument("--out", default=os.path.join(ROOT, "docs", "data", "timesfm-lotto.json"))
  args = parser.parse_args()

  from timesfm3 import ModelConfig, TimesFM3Evaluator
  print("caricamento di TimesFM 3.0…", flush=True)
  forecaster = TimesFM3Evaluator(ModelConfig(
    checkpoint_path="google/timesfm-3.0-pytorch",
    per_core_batch_size=8, device="cpu"))

  report = {
    "modello": "TimesFM 3.0 (google/timesfm-3.0-pytorch)",
    "contesto": args.context,
    "estrazioniValutate": args.steps,
    "eseguitoIl": time.strftime("%d/%m/%Y"),
  }

  if args.solo_controllo_negativo:
    print("controllo negativo su estrazioni puramente casuali…", flush=True)
    noise = uniform_draws(args.context + args.steps + 50)
    report["controlloNegativo"] = run(noise, "rumore", forecaster, args.steps, args.context)
    for row in report["controlloNegativo"]:
      print("   ", row["nome"], "->", row["centriPerEstrazione"], "centri/estrazione",
            "auc", row["auc"], "corr(valore)", row.get("correlazioneConIlValore"),
            "z", row.get("zCorrelazione"), flush=True)
    with open(args.out, "w", encoding="utf-8") as handle:
      json.dump(report, handle, ensure_ascii=False, indent=2)
      handle.write("\n")
    print("scritto:", args.out)
    return

  if not args.skip_control:
    print("controllo positivo su estrazioni sintetiche prevedibili…", flush=True)
    control = synthetic_draws(args.context + args.steps + 50)
    report["controllo"] = run(control, "controllo", forecaster, args.steps, args.context)
    for row in report["controllo"]:
      print("   ", row["nome"], "->", row["centriPerEstrazione"], "centri/estrazione",
            "auc", row["auc"], flush=True)

  print("estrazioni vere, ruota %s…" % args.wheel, flush=True)
  draws = load_wheel(args.wheel, args.since, args.until)
  report["ruota"] = args.wheel
  if args.since or args.until:
    report["periodo"] = {"da": args.since, "a": args.until}
  report["storico"] = {"estrazioni": len(draws), "dal": draws[0][0], "al": draws[-1][0]}
  report["reale"] = run(draws, "ruota " + args.wheel, forecaster, args.steps, args.context)
  for row in report["reale"]:
    print("   ", row["nome"], "->", row["centriPerEstrazione"], "centri/estrazione",
          "auc", row["auc"], "p", row["p"],
          "corr(valore)", row.get("correlazioneConIlValore"),
          "z", row.get("zCorrelazione"), flush=True)

  with open(args.out, "w", encoding="utf-8") as handle:
    json.dump(report, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
  print("scritto:", args.out)


if __name__ == "__main__":
  main()
