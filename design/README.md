# Canvas di progetto — direzione «terminale dati»

Ridisegno dell'interfaccia di Lotto AI Analyzer. Ogni `.dc.html` è una schermata;
`canvas.json` ne descrive la disposizione sulla tavola.

| File | Schermata |
|---|---|
| `Main.dc.html` | Home |
| `Analisi.dc.html` | Frequenze, scostamento dall'atteso, ritardi, tabella |
| `Ambi.dc.html` | Top ambi con il «Perché» |
| `Cinquina.dc.html` | Generatore, quattro modalità |
| `Risultato.dc.html` | Indice statistico e scomposizione |
| `Backtest.dc.html` | Verdetto, curva del saldo, risultati teorici |
| `AIAnalyst.dc.html` | AUC, metriche, verdetto |
| `DashboardChiaro.dc.html` | Home in tema chiaro |
| `Sistema.dc.html` | Palette, tipografia, componenti |

## Rigenerare

Gli artboard non si scrivono a mano: li assemblano gli script, che condividono
palette, tipografia e icone da `_build_common.py`.

```bash
cd design
python3 build_1.py && python3 build_2.py && python3 build_3.py
```

Poi si semina il canvas con l'helper della skill `/design` e si ripubblica sullo
stesso indirizzo. Il file `.html` prodotto pesa 2,6 MB (contiene l'editor) ed è
escluso dal repository: è un prodotto di compilazione, non un sorgente.

## Scelte di progetto

- **Nessun carattere remoto.** SF Mono e SF Pro sono nativi su iPhone, sono giusti
  per un terminale e sono gli unici che l'export PNG/PDF sa incorporare.
- **Chip quadrati** invece delle palline: il colore del bordo porta la fascia
  dell'indice, la forma allontana l'app dall'immaginario della tombola.
- **Scostamento dall'atteso** invece dell'istogramma delle frequenze: con 90 valori
  tutti vicini alla media un istogramma classico è un blocco pieno.
- **Il verdetto è un titolo**, non una nota a piè di pagina.
- I dati mostrati sono inventati ma coerenti fra le schermate: 627 estrazioni per
  ruota (6.897 su 11 ruote), uscite attese 34,8, frequenza attesa 5,56%, uscite
  congiunte attese per coppia 1,6.
