# Script di preparazione dei dati

Ricostruiscono i file in [`docs/data/`](../docs/data). Servono solo per aggiornare lo
storico incluso nell'app: chi usa l'app non deve eseguirli.

```sh
python3 tools/fetch_lotto.py            # docs/data/lotto-storico.csv
python3 tools/fetch_superenalotto.py    # docs/data/superenalotto-storico.csv
python3 tools/build_manifest.py         # docs/data/manifest.json
```

Nessuna dipendenza esterna: solo la libreria standard di Python 3.

- `fetch_lotto.py` scarica `storico.zip` dall'archivio ufficiale del Lotto e lo
  converte. Accetta anche un percorso locale come argomento, se lo zip è già stato
  scaricato.
- `fetch_superenalotto.py` legge l'archivio ufficiale Sisal (dal 2009) e quello di
  `estrazionilottooggi.it` (dal 1997), **confronta le due fonti sugli anni in comune**
  e si ferma se non coincidono. Le pagine scaricate finiscono in `.cache/` (ignorata da
  git), così una nuova esecuzione scarica solo quello che manca. Le due sorgenti
  rispondono lentamente: la prima esecuzione completa richiede circa un'ora.
- `build_manifest.py` rilegge i due CSV e scrive il manifesto che la schermata Dati
  mostra prima di scaricare i file.

---

## TimesFM

`timesfm_lotto.py` e `timesfm_previsione.py` mettono alla prova
[TimesFM 3.0](https://github.com/google-research/timesfm), il modello di
forecasting per serie temporali di Google Research, sulle estrazioni del Lotto.
Questi due, a differenza dei precedenti, hanno dipendenze pesanti: TimesFM
stesso, PyTorch e un checkpoint da 1,3 GB su Hugging Face.

```sh
git clone https://github.com/google-research/timesfm.git
cd timesfm && python3 -m venv .venv
.venv/bin/pip install --index-url https://download.pytorch.org/whl/cpu torch
.venv/bin/pip install -e .

# valutazione walk-forward (circa 45 minuti su 4 CPU)
.venv/bin/python ../lotto/tools/timesfm_lotto.py --steps 150 --wheel BA

# numeri previsti per la prossima estrazione di ogni ruota (circa 2 minuti)
.venv/bin/python ../lotto/tools/timesfm_previsione.py
```

Producono `docs/data/timesfm-lotto.json` (la misura) e
`docs/data/timesfm-previsioni.json` (i numeri più la misura). L'app legge il
secondo e mostra sempre le due cose insieme.

`timesfm_lotto.py` include un **controllo positivo**: la stessa identica
procedura su estrazioni sintetiche costruite per essere prevedibili. Senza,
un risultato negativo sui dati veri non si distinguerebbe da una procedura
rotta. Il pesi di TimesFM hanno una licenza propria, diversa dall'Apache 2.0 del
codice: vedi il repository di Google.
