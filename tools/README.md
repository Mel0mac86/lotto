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
