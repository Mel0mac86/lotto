#!/usr/bin/env python3
"""I numeri che TimesFM 3.0 prevede per la prossima estrazione, ruota per ruota.

    python3 tools/timesfm_previsione.py

Prende le ultime estrazioni di ogni ruota, le dà a TimesFM nelle tre codifiche
di `timesfm_lotto.py` e scrive in docs/data/timesfm-previsioni.json i numeri con
il punteggio più alto.

Attenzione a che cosa è questo file. È l'uscita di un modello di forecasting
applicato a una sequenza casuale: `timesfm_lotto.py` misura quanto vale, e la
misura è riportata dentro lo stesso file accanto ai numeri. L'app mostra le due
cose insieme, mai i numeri da soli."""
import argparse
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from timesfm_lotto import (  # noqa: E402
  CSV, DRAWN, NUMBERS, ROOT, SIGN, build_matrices, load_wheel)

WHEELS = [("BA", "Bari"), ("CA", "Cagliari"), ("FI", "Firenze"), ("GE", "Genova"),
          ("MI", "Milano"), ("NA", "Napoli"), ("PA", "Palermo"), ("RM", "Roma"),
          ("TO", "Torino"), ("VE", "Venezia"), ("RN", "Nazionale")]

TOP = 10


def ranks_from_scores(scores):
  """Posizione di ciascun numero, 1 = punteggio più alto."""
  order = sorted(range(NUMBERS), key=lambda n: scores[n], reverse=True)
  ranks = [0] * NUMBERS
  for position, n in enumerate(order):
    ranks[n] = position + 1
  return ranks


def forecast_wheel(forecaster, draws, context):
  matrices = build_matrices(draws)
  contexts, keys = [], []
  for key, matrix in matrices.items():
    window = matrix[len(draws) - context:].T.astype(np.float32)
    contexts.append(np.ascontiguousarray(window))
    keys.append(key)

  outputs = list(forecaster.predict_batch(
    contexts, horizon=1, return_quantiles=False,
    use_symmetric_averaging=False, make_positive=False))

  per_encoding = {}
  all_ranks = []
  for key, output in zip(keys, outputs):
    scores = (np.asarray(output.forecast).reshape(NUMBERS) * SIGN[key]).tolist()
    ranks = ranks_from_scores(scores)
    all_ranks.append(ranks)
    order = sorted(range(NUMBERS), key=lambda n: scores[n], reverse=True)
    per_encoding[key] = [n + 1 for n in order[:TOP]]

  # Sintesi: media delle posizioni nelle tre codifiche.
  mean_rank = [sum(r[n] for r in all_ranks) / len(all_ranks) for n in range(NUMBERS)]
  combined = sorted(range(NUMBERS), key=lambda n: mean_rank[n])
  return {
    "perCodifica": per_encoding,
    "combinata": [n + 1 for n in combined[:TOP]],
    "cinquina": sorted(n + 1 for n in combined[:DRAWN]),
  }


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--context", type=int, default=512)
  parser.add_argument("--out", default=os.path.join(ROOT, "docs", "data", "timesfm-previsioni.json"))
  parser.add_argument("--valutazione",
                      default=os.path.join(ROOT, "docs", "data", "timesfm-lotto.json"))
  args = parser.parse_args()

  from timesfm3 import ModelConfig, TimesFM3Evaluator
  print("caricamento di TimesFM 3.0…", flush=True)
  forecaster = TimesFM3Evaluator(ModelConfig(
    checkpoint_path="google/timesfm-3.0-pytorch",
    per_core_batch_size=8, device="cpu"))

  wheels = {}
  last_date = None
  for code, name in WHEELS:
    draws = load_wheel(code)
    if len(draws) < args.context:
      print("  %s: storico insufficiente, saltata" % name, flush=True)
      continue
    began = time.time()
    wheels[name] = forecast_wheel(forecaster, draws, args.context)
    wheels[name]["ultimaEstrazioneVista"] = draws[-1][0]
    last_date = max(last_date or draws[-1][0], draws[-1][0])
    print("  %-10s %s   (%.1f s)" % (name, wheels[name]["cinquina"],
                                     time.time() - began), flush=True)

  payload = {
    "modello": "TimesFM 3.0 (google/timesfm-3.0-pytorch)",
    "contesto": args.context,
    "generatoIl": time.strftime("%d/%m/%Y"),
    "ultimaEstrazioneVista": last_date,
    "ruote": wheels,
  }

  # La misura di quanto vale questa previsione viaggia insieme alla previsione.
  if os.path.exists(args.valutazione):
    with open(args.valutazione, encoding="utf-8") as handle:
      payload["valutazione"] = json.load(handle)

  with open(args.out, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
  print("scritto:", args.out)


if __name__ == "__main__":
  main()
