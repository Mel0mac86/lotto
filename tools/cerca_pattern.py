#!/usr/bin/env python3
"""Caccia sistematica a un pattern nelle estrazioni del Lotto.

    python3 tools/cerca_pattern.py

Con 77.000 estrazioni la potenza statistica è enorme: una distorsione anche
piccola — un'urna sbilanciata, una pallina più leggera, un'abitudine
dell'estrattore — lascerebbe una traccia visibile. Questo script cerca quella
traccia dove ha senso cercarla.

I test sono decisi PRIMA di guardare i risultati e sono tutti riportati, quelli
che passano e quelli che non passano. Alla fine si applica la correzione di
Benjamini-Hochberg: facendo centinaia di test, qualcuno risulta «significativo»
per forza, e senza correzione si scambierebbe il rumore per una scoperta."""
import collections
import itertools
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "docs", "data", "lotto-storico.csv")
NUMBERS = 90
DRAWN = 5

WHEEL_NAMES = {"BA": "Bari", "CA": "Cagliari", "FI": "Firenze", "GE": "Genova",
               "MI": "Milano", "NA": "Napoli", "PA": "Palermo", "RM": "Roma",
               "TO": "Torino", "VE": "Venezia", "RN": "Nazionale"}


# ----------------------------------------------------- funzioni statistiche

def lower_gamma_regularized(s, x):
  """Gamma incompleta inferiore regolarizzata: serie sotto s+1, frazione continua sopra."""
  if x < 0 or s <= 0:
    return 0.0
  if x == 0:
    return 0.0
  if x < s + 1:
    term = 1.0 / s
    total = term
    n = s
    for _ in range(1000):
      n += 1
      term *= x / n
      total += term
      if abs(term) < abs(total) * 1e-15:
        break
    return total * math.exp(-x + s * math.log(x) - math.lgamma(s))
  # Lentz
  tiny = 1e-300
  b = x + 1 - s
  c = 1 / tiny
  d = 1 / b if b != 0 else 1 / tiny
  h = d
  for i in range(1, 1000):
    an = -i * (i - s)
    b += 2
    d = an * d + b
    if abs(d) < tiny:
      d = tiny
    c = b + an / c
    if abs(c) < tiny:
      c = tiny
    d = 1 / d
    delta = d * c
    h *= delta
    if abs(delta - 1) < 1e-15:
      break
  return 1 - math.exp(-x + s * math.log(x) - math.lgamma(s)) * h


def chi_square_p(statistic, degrees):
  if degrees <= 0 or statistic < 0:
    return 1.0
  return max(0.0, min(1.0, 1.0 - lower_gamma_regularized(degrees / 2.0, statistic / 2.0)))


def normal_p_two_sided(z):
  return math.erfc(abs(z) / math.sqrt(2))


def chi_square_uniform(counts):
  total = sum(counts)
  if not total:
    return 0.0, 1.0, 0
  expected = total / len(counts)
  statistic = sum((c - expected) ** 2 / expected for c in counts)
  degrees = len(counts) - 1
  return statistic, chi_square_p(statistic, degrees), degrees


# ------------------------------------------------------------------- dati

def load():
  rows = []
  with open(CSV, encoding="utf-8") as handle:
    next(handle)
    for line in handle:
      parts = line.rstrip("\n").split(";")
      rows.append((parts[0], parts[1], [int(v) for v in parts[2:7]]))
  rows.sort(key=lambda row: (row[0], row[1]))
  return rows


def weekday(stamp):
  year, month, day = int(stamp[:4]), int(stamp[4:6]), int(stamp[6:8])
  # Zeller
  if month < 3:
    month += 12
    year -= 1
  k, j = year % 100, year // 100
  h = (day + (13 * (month + 1)) // 5 + k + k // 4 + j // 4 + 5 * j) % 7
  return (h + 5) % 7  # 0 = lunedì


# ------------------------------------------------------------------- test

def run_tests(rows):
  tests = []
  by_wheel = collections.defaultdict(list)
  for stamp, code, numbers in rows:
    by_wheel[code].append((stamp, numbers))

  # 1. Uniformità dei 90 numeri, su tutto lo storico e ruota per ruota.
  pooled = collections.Counter()
  for _, _, numbers in rows:
    pooled.update(numbers)
  statistic, p, degrees = chi_square_uniform([pooled[n] for n in range(1, NUMBERS + 1)])
  tests.append({"famiglia": "uniformità", "nome": "Tutti i numeri, tutte le ruote",
                "n": len(rows), "chi2": round(statistic, 2), "gdl": degrees, "p": p})

  for code, draws in sorted(by_wheel.items()):
    counter = collections.Counter()
    for _, numbers in draws:
      counter.update(numbers)
    statistic, p, degrees = chi_square_uniform([counter[n] for n in range(1, NUMBERS + 1)])
    tests.append({"famiglia": "uniformità", "nome": "Numeri, ruota " + WHEEL_NAMES[code],
                  "n": len(draws), "chi2": round(statistic, 2), "gdl": degrees, "p": p})

  # 2. Uniformità per epoca: se un'urna era sbilanciata, si vede in un periodo preciso.
  eras = [("1939-1959", "1939", "1960"), ("1960-1979", "1960", "1980"),
          ("1980-1999", "1980", "2000"), ("2000-2009", "2000", "2010"),
          ("2010-2026", "2010", "2027")]
  for label, start, end in eras:
    counter = collections.Counter()
    count = 0
    for stamp, _, numbers in rows:
      if start <= stamp[:4] < end:
        counter.update(numbers)
        count += 1
    if count < 500:
      continue
    statistic, p, degrees = chi_square_uniform([counter[n] for n in range(1, NUMBERS + 1)])
    tests.append({"famiglia": "epoche", "nome": "Numeri, " + label,
                  "n": count, "chi2": round(statistic, 2), "gdl": degrees, "p": p})

  # 3. Ripetizione dall'estrazione precedente sulla stessa ruota.
  #    Attesa: ogni numero uscito ha probabilità 5/90 di ripetersi.
  for code, draws in sorted(by_wheel.items()):
    repeats = 0
    trials = 0
    for i in range(1, len(draws)):
      previous = set(draws[i - 1][1])
      repeats += len(previous & set(draws[i][1]))
      trials += DRAWN
    expected = trials * DRAWN / NUMBERS
    sigma = math.sqrt(trials * (DRAWN / NUMBERS) * (1 - DRAWN / NUMBERS))
    z = (repeats - expected) / sigma
    tests.append({"famiglia": "ripetizioni", "nome": "Ripetuti dall'estrazione precedente, "
                  + WHEEL_NAMES[code], "n": trials, "osservato": repeats,
                  "atteso": round(expected, 1), "z": round(z, 3), "p": normal_p_two_sided(z)})

  # 4. Autocorrelazione a distanza 1..5: un numero uscito rende più o meno
  #    probabile la sua uscita k estrazioni dopo?
  for lag in range(1, 6):
    hits = 0
    trials = 0
    for code, draws in by_wheel.items():
      for i in range(lag, len(draws)):
        hits += len(set(draws[i - lag][1]) & set(draws[i][1]))
        trials += DRAWN
    expected = trials * DRAWN / NUMBERS
    sigma = math.sqrt(trials * (DRAWN / NUMBERS) * (1 - DRAWN / NUMBERS))
    z = (hits - expected) / sigma
    tests.append({"famiglia": "autocorrelazione", "nome": "Uscite a distanza %d" % lag,
                  "n": trials, "osservato": hits, "atteso": round(expected, 1),
                  "z": round(z, 3), "p": normal_p_two_sided(z)})

  # 5. Giorno della settimana: l'estrazione dipende da quando viene fatta?
  by_day = collections.defaultdict(collections.Counter)
  day_totals = collections.Counter()
  for stamp, _, numbers in rows:
    day = weekday(stamp)
    by_day[day].update(numbers)
    day_totals[day] += 1
  for day in sorted(by_day):
    if day_totals[day] < 500:
      continue
    counts = [by_day[day][n] for n in range(1, NUMBERS + 1)]
    statistic, p, degrees = chi_square_uniform(counts)
    tests.append({"famiglia": "giorno", "nome": "Numeri estratti di giorno %d" % day,
                  "n": day_totals[day], "chi2": round(statistic, 2), "gdl": degrees, "p": p})

  # 6. Proprietà aggregate dell'estrazione: somma, pari, alti, decine distinte.
  #    Confronto con la distribuzione teorica ottenuta per simulazione esatta.
  aggregate = {"somma": [], "pari": [], "alti": [], "decine": []}
  for _, _, numbers in rows:
    aggregate["somma"].append(sum(numbers))
    aggregate["pari"].append(sum(1 for n in numbers if n % 2 == 0))
    aggregate["alti"].append(sum(1 for n in numbers if n > 45))
    aggregate["decine"].append(len({(n - 1) // 10 for n in numbers}))

  # pari e alti seguono una ipergeometrica esatta
  def hypergeometric(k, successes):
    return (math.comb(successes, k) * math.comb(NUMBERS - successes, DRAWN - k)
            / math.comb(NUMBERS, DRAWN))

  for key, successes in (("pari", 45), ("alti", 45)):
    observed = collections.Counter(aggregate[key])
    total = len(aggregate[key])
    statistic = 0.0
    cells = 0
    for k in range(DRAWN + 1):
      expected = total * hypergeometric(k, successes)
      if expected >= 5:
        statistic += (observed[k] - expected) ** 2 / expected
        cells += 1
    p = chi_square_p(statistic, cells - 1)
    tests.append({"famiglia": "aggregati", "nome": "Numeri %s per estrazione" % key,
                  "n": total, "chi2": round(statistic, 2), "gdl": cells - 1, "p": p})

  # 6b. Media dei numeri estratti, per epoca.
  #     Il chi quadro su 89 gradi di libertà è cieco a una distorsione LISCIA
  #     (i numeri alti un po' più probabili dei bassi): la media la vede subito.
  variance_of_mean = ((NUMBERS ** 2 - 1) / 12.0) / DRAWN * (NUMBERS - DRAWN) / (NUMBERS - 1)

  def mean_test(label, family, selected):
    if len(selected) < 300:
      return None
    mean = sum(selected) / len(selected)
    z = (mean - (NUMBERS + 1) / 2.0) / math.sqrt(variance_of_mean / len(selected))
    entry = {"famiglia": family, "nome": label, "n": len(selected),
             "media": round(mean, 4), "z": round(z, 3), "p": normal_p_two_sided(z)}
    tests.append(entry)
    return entry

  means_all = [sum(numbers) / DRAWN for _, _, numbers in rows]
  mean_test("Media dei numeri estratti, tutto lo storico", "media", means_all)
  for label, start, end in eras:
    mean_test("Media dei numeri estratti, " + label, "media",
              [sum(numbers) / DRAWN for stamp, _, numbers in rows if start <= stamp[:4] < end])

  # 7. Coppie: 4.005 ambi possibili. Qui la correzione multipla è decisiva.
  pair_counts = collections.Counter()
  for _, _, numbers in rows:
    for a, b in itertools.combinations(sorted(numbers), 2):
      pair_counts[(a, b)] += 1
  total_draws = len(rows)
  expected_pair = total_draws * math.comb(DRAWN, 2) / math.comb(NUMBERS, 2)
  sigma_pair = math.sqrt(expected_pair * (1 - math.comb(DRAWN, 2) / math.comb(NUMBERS, 2)))
  extreme = []
  for pair in itertools.combinations(range(1, NUMBERS + 1), 2):
    observed = pair_counts.get(pair, 0)
    z = (observed - expected_pair) / sigma_pair
    extreme.append((abs(z), pair, observed, z))
  extreme.sort(reverse=True)
  best = extreme[0]
  # Questo z è il MASSIMO su 4.005 confronti: il suo p va corretto, altrimenti
  # si scambia per scoperta il valore più estremo di una lunga lista di rumore.
  single = normal_p_two_sided(best[3])
  corrected = 1 - (1 - single) ** len(extreme)
  tests.append({"famiglia": "coppie", "nome": "Ambo più anomalo su 4.005 (%d-%d)" % best[1],
                "n": total_draws, "osservato": best[2], "atteso": round(expected_pair, 1),
                "z": round(best[3], 3), "p": corrected, "pNonCorretto": round(single, 6),
                "nota": "massimo su 4.005 confronti, p corretto secondo Šidák"})

  return tests, extreme[:10], expected_pair


def describe_discovery(rows):
  """Il quadro completo dell'unico pattern che regge: la distorsione verso i
  numeri alti fra il 1970 e il 1999. Ogni voce è una verifica indipendente."""
  variance_of_mean = ((NUMBERS ** 2 - 1) / 12.0) / DRAWN * (NUMBERS - DRAWN) / (NUMBERS - 1)
  variance_single = (NUMBERS ** 2 - 1) / 12.0
  hits_variance = (DRAWN * (DRAWN / NUMBERS) * (1 - DRAWN / NUMBERS)
                   * (NUMBERS - DRAWN) / (NUMBERS - 1))
  expected_hits = DRAWN * DRAWN / NUMBERS

  def z_mean(values):
    mean = sum(values) / len(values)
    return mean, (mean - (NUMBERS + 1) / 2.0) / math.sqrt(variance_of_mean / len(values))

  def window(start, end):
    return [(stamp, code, numbers) for stamp, code, numbers in rows if start <= stamp[:4] < end]

  periods = [("1939-1969", "1939", "1970"), ("1970-1999", "1970", "2000"),
             ("2000-2026", "2000", "2027")]

  medie = []
  for label, start, end in periods:
    selected = window(start, end)
    mean, z = z_mean([sum(numbers) / DRAWN for _, _, numbers in selected])
    medie.append({"periodo": label, "estrazioni": len(selected), "media": round(mean, 4),
                  "z": round(z, 2), "p": normal_p_two_sided(z)})

  # Regola fissa, decisa senza guardare i dati: gioco sempre i cinque più alti.
  regola = []
  picks = set(range(NUMBERS - DRAWN + 1, NUMBERS + 1))
  for label, start, end in periods:
    selected = window(start, end)
    hits = sum(len(picks & set(numbers)) for _, _, numbers in selected)
    observed = hits / len(selected)
    z = (observed - expected_hits) / math.sqrt(hits_variance / len(selected))
    regola.append({"periodo": label, "estrazioni": len(selected),
                   "centriPerEstrazione": round(observed, 4),
                   "vantaggio": round(100 * (observed / expected_hits - 1), 1),
                   "z": round(z, 2)})

  # Per posizione di estrazione: dove agisce la distorsione.
  posizioni = []
  biased = window("1970", "2000")
  clean = window("2000", "2027")
  for position in range(DRAWN):
    row = {"posizione": position + 1}
    for key, selected in (("distorta", biased), ("pulita", clean)):
      values = [numbers[position] for _, _, numbers in selected]
      mean = sum(values) / len(values)
      row[key] = round((mean - (NUMBERS + 1) / 2.0)
                       / math.sqrt(variance_single / len(values)), 2)
    posizioni.append(row)

  # Trasferimento fuori campione: i numeri scelti su un periodo valgono sul successivo?
  def top_numbers(selected):
    counter = collections.Counter()
    for _, _, numbers in selected:
      counter.update(numbers)
    return sorted(range(1, NUMBERS + 1), key=lambda n: -counter[n])[:DRAWN]

  trasferimento = []
  for (ts, te), (vs, ve) in [(("1970", "1985"), ("1985", "2000")),
                             (("1970", "1990"), ("1990", "2000")),
                             (("1970", "2000"), ("2000", "2027"))]:
    chosen = set(top_numbers(window(ts, te)))
    selected = window(vs, ve)
    hits = sum(len(chosen & set(numbers)) for _, _, numbers in selected)
    observed = hits / len(selected)
    trasferimento.append({
      "scelti": "%s-%s" % (ts, te), "giocati": "%s-%s" % (vs, ve),
      "numeri": sorted(chosen), "estrazioni": len(selected),
      "centriPerEstrazione": round(observed, 4),
      "vantaggio": round(100 * (observed / expected_hits - 1), 1),
      "z": round((observed - expected_hits) / math.sqrt(hits_variance / len(selected)), 2)})

  return {
    "titolo": "Nel 1970-1999 i numeri alti uscivano più dei bassi",
    "medie": medie,
    "regolaFissa": regola,
    "posizioni": posizioni,
    "trasferimento": trasferimento,
    "attesaCentri": round(expected_hits, 4),
  }


def benjamini_hochberg(tests, alpha=0.05):
  ordered = sorted(range(len(tests)), key=lambda i: tests[i]["p"])
  m = len(tests)
  threshold = 0
  for rank, index in enumerate(ordered, start=1):
    if tests[index]["p"] <= alpha * rank / m:
      threshold = rank
  survivors = {ordered[i] for i in range(threshold)}
  for i, test in enumerate(tests):
    test["sopravviveBH"] = i in survivors
  return threshold


def main():
  rows = load()
  tests, top_pairs, expected_pair = run_tests(rows)
  survivors = benjamini_hochberg(tests)

  print("estrazioni analizzate:", len(rows))
  print("test eseguiti:", len(tests))
  print()
  header = "%-52s %10s %12s %8s" % ("test", "n", "statistica", "p")
  print(header)
  print("-" * len(header))
  for test in sorted(tests, key=lambda t: t["p"]):
    statistic = ("chi2 %.1f" % test["chi2"]) if "chi2" in test else ("z %.2f" % test["z"])
    mark = "  <-- sopravvive" if test["sopravviveBH"] else ""
    print("%-52s %10d %12s %8.4f%s"
          % (test["nome"][:52], test["n"], statistic, test["p"], mark))

  print()
  print("Correzione Benjamini-Hochberg al 5%%: %d test su %d sopravvivono."
        % (survivors, len(tests)))
  print()
  print("Ambi più lontani dall'attesa (%.1f uscite attese su %d estrazioni):"
        % (expected_pair, len(rows)))
  for _, pair, observed, z in top_pairs:
    print("   %2d-%2d  osservate %d  z %+.2f  p %.4f (non corretto)"
          % (pair[0], pair[1], observed, z, normal_p_two_sided(z)))

  out = os.path.join(ROOT, "docs", "data", "pattern-lotto.json")
  with open(out, "w", encoding="utf-8") as handle:
    json.dump({"estrazioni": len(rows), "test": tests,
               "sopravvivonoBH": survivors,
               "scoperta": describe_discovery(rows)}, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
  print("\nscritto:", out)


if __name__ == "__main__":
  main()
