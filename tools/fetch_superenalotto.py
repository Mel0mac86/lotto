#!/usr/bin/env python3
"""Costruisce docs/data/superenalotto-storico.csv da due archivi pubblici.

    python3 tools/fetch_superenalotto.py [cartella-cache]

L'archivio ufficiale (superenalotto.it, Sisal) è consultabile per mese ma solo
dal 2009 in poi. Per il periodo 1997-2008 si usa l'archivio di
estrazionilottooggi.it, che parte dalla prima estrazione del 3 dicembre 1997.

Le due fonti vengono confrontate riga per riga sugli anni in comune: se non
coincidono lo script si ferma, perché a quel punto la fonte secondaria non
sarebbe affidabile nemmeno per gli anni che copre da sola."""
import collections
import concurrent.futures
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "data", "superenalotto-storico.csv")

MESI = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
        "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
MESE_NUMERO = {name: index + 1 for index, name in enumerate(MESI)}

OFFICIAL_FROM = 2009
SECONDARY_UNTIL = 2011  # copre 1997-2008 e tre anni di sovrapposizione per il confronto

# --- Fonte ufficiale: superenalotto.it/archivio-estrazioni/<anno>/<mese>
OFFICIAL_ROW = re.compile(
    r'<tr class="superenalotto-extraction-archive__details__table__row.*?</tr>', re.S)
OFFICIAL_LABEL = re.compile(
    r'Concorso\s*<strong>N[º°]\s*(\d+)</strong>\s*del\s*<strong>\s*([^<]+?)\s*</strong>', re.S)
OFFICIAL_COMB = re.compile(r'__combination__text">\s*(\d+)\s*<')
OFFICIAL_JOLLY = re.compile(r'__jolly__text">\s*(\d+)\s*<')
OFFICIAL_STAR = re.compile(r'__superstar__text">\s*(\d+)\s*<')

# --- Fonte secondaria: estrazionilottooggi.it/superenalotto/Archivio-superenalotto-<anno>
# Fra il titolo e la tabella non deve esserci un altro titolo, altrimenti si
# starebbe leggendo la tabella di un'estrazione diversa.
SECONDARY_HEAD = re.compile(
    r'Estrazione Superenalotto del (\d{1,2}) ([A-Za-zàèéìòù]+) (\d{4}) - n\.\s*(\d+)</a>'
    r'((?:(?!Estrazione Superenalotto del).){0,1200}?)</table>', re.S)
SECONDARY_CELL = re.compile(r'<td[^>]*>\s*(\d*)\s*</td>')


def fetch(url, path, minimum):
    """Scarica una pagina, con cache su disco e qualche tentativo: i due siti
    rispondono lentamente e ogni tanto chiudono la connessione."""
    if os.path.exists(path) and os.path.getsize(path) >= minimum:
        return open(path, encoding="utf-8", errors="replace").read()
    request = urllib.request.Request(url, headers={"User-Agent": "lotto-ai-analyzer/1.0"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                payload = response.read()
            if len(payload) >= minimum:
                with open(path, "wb") as handle:
                    handle.write(payload)
                return payload.decode("utf-8", errors="replace")
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(5 * (attempt + 1))
    return None


def read_official(cache):
    draws, problems = {}, collections.Counter()
    directory = os.path.join(cache, "ufficiale")
    os.makedirs(directory, exist_ok=True)
    year_now = time.gmtime().tm_year
    jobs = [(year, month) for year in range(OFFICIAL_FROM, year_now + 1) for month in range(1, 13)]

    def load(job):
        year, month = job
        url = "https://www.superenalotto.it/archivio-estrazioni/%d/%s" % (year, MESI[month - 1])
        path = os.path.join(directory, "%d-%02d.html" % (year, month))
        return fetch(url, path, 50000)

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        pages = list(pool.map(load, jobs))

    for html in pages:
        if html is None:
            problems["pagina non scaricata"] += 1
            continue
        for block in OFFICIAL_ROW.findall(html):
            label = OFFICIAL_LABEL.search(block)
            if not label:
                problems["etichetta illeggibile"] += 1
                continue
            day, month_name, year = label.group(2).split()
            month = MESE_NUMERO.get(month_name.lower())
            numbers = [int(value) for value in OFFICIAL_COMB.findall(block)]
            if not numbers:
                # L'archivio elenca anche i concorsi in calendario non ancora estratti.
                problems["concorso non ancora estratto"] += 1
                continue
            if month is None or len(numbers) != 6 or len(set(numbers)) != 6 \
               or not all(1 <= n <= 90 for n in numbers):
                problems["estrazione non valida"] += 1
                continue
            jolly = OFFICIAL_JOLLY.search(block)
            star = OFFICIAL_STAR.search(block)
            stamp = "%04d%02d%02d" % (int(year), month, int(day))
            draws[stamp] = (int(label.group(1)), numbers,
                            int(jolly.group(1)) if jolly else None,
                            int(star.group(1)) if star else None)
    return draws, problems


def read_secondary(cache):
    draws, problems = {}, collections.Counter()
    directory = os.path.join(cache, "secondaria")
    os.makedirs(directory, exist_ok=True)

    for year in range(1997, SECONDARY_UNTIL + 1):
        offset = 0
        while True:
            suffix = "" if offset == 0 else "/(offset)/%d" % offset
            url = ("http://www.estrazionilottooggi.it/superenalotto/"
                   "Archivio-superenalotto-%d%s" % (year, suffix))
            path = os.path.join(directory, "%d-%03d.html" % (year, offset))
            html = fetch(url, path, 15000)
            if html is None:
                problems["pagina non scaricata"] += 1
                break
            found = 0
            for day, month_name, page_year, contest, body in SECONDARY_HEAD.findall(html):
                month = MESE_NUMERO.get(month_name.lower())
                values = [cell for cell in SECONDARY_CELL.findall(body)]
                while values and values[0] == "":
                    values.pop(0)  # la prima riga della tabella è un segnaposto vuoto
                if month is None or len(values) < 6:
                    problems["riga illeggibile"] += 1
                    continue
                try:
                    numbers = [int(value) for value in values[:6]]
                except ValueError:
                    problems["riga illeggibile"] += 1
                    continue
                if len(set(numbers)) != 6 or not all(1 <= n <= 90 for n in numbers):
                    problems["estrazione non valida"] += 1
                    continue
                stamp = "%04d%02d%02d" % (int(page_year), month, int(day))
                draws[stamp] = (int(contest), numbers,
                                int(values[6]) if len(values) > 6 and values[6] else None,
                                int(values[7]) if len(values) > 7 and values[7] else None)
                found += 1
            if found < 30:
                break
            offset += 30
    return draws, problems


def compare(official, secondary):
    """Discordanze sugli anni in comune. Lo SuperStar non c'era prima del 2006 e
    manca in entrambe le fonti su parte dello storico: si confronta solo quando
    è presente da entrambe le parti."""
    overlap = sorted(set(official) & set(secondary))
    mismatch = collections.Counter()
    examples = []
    for stamp in overlap:
        left, right = official[stamp], secondary[stamp]
        for index, name in ((0, "concorso"), (1, "combinazione"), (2, "jolly")):
            if left[index] != right[index]:
                mismatch[name] += 1
                if len(examples) < 8:
                    examples.append((stamp, name, left[index], right[index]))
        if left[3] is not None and right[3] is not None and left[3] != right[3]:
            mismatch["superstar"] += 1
            if len(examples) < 8:
                examples.append((stamp, "superstar", left[3], right[3]))
    return overlap, mismatch, examples


def main():
    cache = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".cache", "superenalotto")
    os.makedirs(cache, exist_ok=True)

    official, official_problems = read_official(cache)
    print("ufficiale:", len(official), "· problemi:", dict(official_problems) or "nessuno")
    if not official:
        sys.exit("nessuna pagina ufficiale leggibile: controlla la connessione")

    secondary, secondary_problems = read_secondary(cache)
    print("secondaria:", len(secondary), "· problemi:", dict(secondary_problems) or "nessuno")

    overlap, mismatch, examples = compare(official, secondary)
    print("sovrapposizione:", len(overlap), "estrazioni · discordanze:", dict(mismatch) or "nessuna")
    for row in examples:
        print("   ", row)
    if mismatch:
        sys.exit("le due fonti non coincidono: la parte 1997-2008 non è verificabile, mi fermo")
    if len(overlap) < 300:
        sys.exit("sovrapposizione troppo piccola per verificare la fonte secondaria")

    first_official = min(official)
    merged = {stamp: value for stamp, value in secondary.items() if stamp < first_official}
    from_secondary = len(merged)
    merged.update(official)

    rows = sorted(merged.items())
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("data;concorso;numero1;numero2;numero3;numero4;numero5;numero6;jolly;superstar\n")
        for stamp, (contest, numbers, jolly, star) in rows:
            handle.write("%s;%d;%s;%s;%s\n" % (
                stamp, contest, ";".join(str(n) for n in numbers),
                "" if jolly is None else jolly, "" if star is None else star))

    print("totale:", len(rows), "· dalla fonte secondaria (1997-2008):", from_secondary)
    print("periodo:", rows[0][0], "->", rows[-1][0])
    print("senza jolly:", sum(1 for _, value in rows if value[2] is None),
          "· senza superstar:", sum(1 for _, value in rows if value[3] is None))
    print("per anno:", dict(sorted(collections.Counter(stamp[:4] for stamp, _ in rows).items())))
    print("scritto:", OUT)


if __name__ == "__main__":
    main()
