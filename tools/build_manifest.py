#!/usr/bin/env python3
"""Scrive docs/data/manifest.json leggendo i due CSV dello storico.

Il manifesto è quello che la schermata Dati mostra prima di scaricare i file:
quante estrazioni ci sono, che periodo coprono e da dove vengono."""
import collections
import datetime
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "docs", "data")

SOURCES = {
    "lotto": {
        "source": "Archivio storico ufficiale del Lotto (concessionario Brightstar Lottery, ex IGT Lottery S.p.A.)",
        "sourceUrl": "https://www.brightstarlottery.it/STORICO_ESTRAZIONI_LOTTO/storico.zip",
    },
    "superenalotto": {
        "source": "Archivio estrazioni ufficiale Sisal (superenalotto.it) dal 2009; "
                  "per il periodo 1997-2008 archivio di estrazionilottooggi.it, "
                  "verificato riga per riga contro quello ufficiale sugli anni in comune",
        "sourceUrl": "https://www.superenalotto.it/archivio-estrazioni",
    },
}


def italian_date(compact):
    return "%s/%s/%s" % (compact[6:8], compact[4:6], compact[0:4])


def describe(game, filename):
    path = os.path.join(DATA, filename)
    dates = []
    wheels = set()
    rows = 0
    with open(path, encoding="utf-8") as handle:
        next(handle)
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split(";")
            dates.append(parts[0])
            if game == "lotto":
                wheels.add(parts[1])
            rows += 1
    entry = {
        "file": "data/" + filename,
        "draws": rows,
        "firstDate": italian_date(min(dates)),
        "lastDate": italian_date(max(dates)),
        "bytes": os.path.getsize(path),
    }
    if game == "lotto":
        entry["wheels"] = len(wheels)
    else:
        entry["contests"] = len(set(dates))
    entry.update(SOURCES[game])
    return entry


manifest = {
    "retrievedAt": datetime.date.today().strftime("%d/%m/%Y"),
    "note": "Copia locale degli archivi pubblici delle estrazioni. Nessun dato personale.",
    "archives": {
        "lotto": describe("lotto", "lotto-storico.csv"),
        "superenalotto": describe("superenalotto", "superenalotto-storico.csv"),
    },
}

out = os.path.join(DATA, "manifest.json")
with open(out, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(json.dumps(manifest, ensure_ascii=False, indent=2))
