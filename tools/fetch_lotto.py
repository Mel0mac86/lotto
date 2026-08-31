#!/usr/bin/env python3
"""Scarica l'archivio storico ufficiale del Lotto e lo converte nel CSV dell'app.

    python3 tools/fetch_lotto.py

Sorgente: storico.zip pubblicato dal concessionario, contiene un file di testo
con una riga per data e ruota, separata da tabulazioni:

    1939/01/07<TAB>BA<TAB>58<TAB>22<TAB>47<TAB>49<TAB>69

In uscita: docs/data/lotto-storico.csv, con le stesse colonne che l'app
riconosce anche in importazione manuale."""
import collections
import io
import os
import sys
import urllib.request
import zipfile

URL = "https://www.brightstarlottery.it/STORICO_ESTRAZIONI_LOTTO/storico.zip"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "data", "lotto-storico.csv")

# I codici usati nel file ufficiale. RN è la ruota Nazionale.
CODES = {"BA", "CA", "FI", "GE", "MI", "NA", "PA", "RM", "TO", "VE", "RN"}


def download():
    request = urllib.request.Request(URL, headers={"User-Agent": "lotto-ai-analyzer/1.0"})
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read()


def main():
    payload = open(sys.argv[1], "rb").read() if len(sys.argv) > 1 else download()
    archive = zipfile.ZipFile(io.BytesIO(payload))
    name = next(item for item in archive.namelist() if item.lower().endswith(".txt"))
    text = archive.read(name).decode("latin-1")

    rows = []
    rejected = 0
    per_code = collections.Counter()

    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) != 7:
            rejected += 1
            continue
        code = parts[1].strip().upper()
        if code not in CODES:
            rejected += 1
            continue
        try:
            year, month, day = (int(value) for value in parts[0].split("/"))
            numbers = [int(value) for value in parts[2:]]
        except ValueError:
            rejected += 1
            continue
        if len(set(numbers)) != 5 or not all(1 <= n <= 90 for n in numbers):
            rejected += 1
            continue
        rows.append(("%04d%02d%02d" % (year, month, day), code, numbers))
        per_code[code] += 1

    rows.sort(key=lambda row: (row[0], row[1]))
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("data;ruota;numero1;numero2;numero3;numero4;numero5\n")
        for stamp, code, numbers in rows:
            handle.write("%s;%s;%s\n" % (stamp, code, ";".join(str(n) for n in numbers)))

    print("estrazioni:", len(rows), "· righe scartate:", rejected)
    print("periodo:", rows[0][0], "->", rows[-1][0])
    print("ruote:", dict(sorted(per_code.items())))
    print("scritto:", OUT)


if __name__ == "__main__":
    main()
