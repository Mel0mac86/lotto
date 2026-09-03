# Script di preparazione dei dati

Ricostruiscono i file in [`docs/data/`](../docs/data). Servono solo per aggiornare lo
storico incluso nell'app: chi usa l'app non deve eseguirli.

```sh
python3 tools/fetch_lotto.py            # docs/data/lotto-storico.csv
python3 tools/fetch_superenalotto.py    # docs/data/superenalotto-storico.csv
python3 tools/build_manifest.py         # docs/data/manifest.json

python3 tools/fetch_superenalotto.py --aggiorna   # solo le estrazioni nuove
```

`--aggiorna` legge il CSV già presente, scarica soltanto gli ultimi due mesi
dall'archivio ufficiale e aggiunge quello che manca: è la modalità usata ogni sera dal
workflow [`aggiorna-estrazioni.yml`](../.github/workflows/aggiorna-estrazioni.yml), che
altrimenti dovrebbe rileggere 216 pagine ogni volta. Lo storico anteriore al 2009 non
viene toccato, quindi non serve riverificare le fonti.

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

## Caccia ai pattern

```sh
python3 tools/cerca_pattern.py          # docs/data/pattern-lotto.json
```

48 test decisi in anticipo su tutte le 77.000 estrazioni, con correzione di
Benjamini-Hochberg per la molteplicità, più il quadro completo dell'unico effetto che
regge alla verifica. Solo libreria standard, qualche secondo. L'app legge il JSON nella
scheda **Trova pattern**.

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

# il modello davanti al pattern vero del 1970-1999, con i suoi controlli
.venv/bin/python ../lotto/tools/timesfm_lotto.py --steps 150 --wheel CA --until 20000101 --skip-control
.venv/bin/python ../lotto/tools/timesfm_lotto.py --steps 150 --wheel CA --from 20000101 --skip-control
.venv/bin/python ../lotto/tools/timesfm_lotto.py --steps 150 --solo-controllo-negativo
```

Producono `docs/data/timesfm-lotto.json` (la misura) e
`docs/data/timesfm-previsioni.json` (i numeri più la misura). L'app legge il
secondo e mostra sempre le due cose insieme.

`timesfm_lotto.py` include **due controlli**, e servono entrambi. Il **positivo**
(estrazioni sintetiche costruite per essere prevedibili) distingue «il modello non trova
nulla» da «la procedura è rotta». Il **negativo** (`--solo-controllo-negativo`,
estrazioni perfettamente casuali) misura il vero livello di rumore delle metriche: senza,
la correlazione col valore del numero sembra rivelare una scoperta dove non c'è, perché
il suo z nominale è gonfiato dalla sovrapposizione fra finestre consecutive. Il pesi di TimesFM hanno una licenza propria, diversa dall'Apache 2.0 del
codice: vedi il repository di Google.
