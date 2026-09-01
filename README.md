# Lotto AI Analyzer

Applicazione iPhone per l'**analisi statistica** degli estratti
del Lotto italiano e del SuperEnalotto.

> **Le estrazioni sono casuali. Le analisi statistiche degli estratti passati non
> modificano la probabilità matematica di vincita. Le combinazioni generate sono
> suggerimenti statistici e non previsioni certe.**

Il repository contiene **due implementazioni della stessa app**:

| | Cartella | Come si usa |
|---|---|---|
| **Web app (PWA)** | [`docs/`](docs/) | Si apre in Safari e si aggiunge alla schermata Home: funziona a schermo intero, offline, **senza Mac né Xcode** |
| **App iOS nativa** | [`LottoAIAnalyzer/`](LottoAIAnalyzer/) | Progetto Xcode in SwiftUI, richiede un Mac con Xcode 16 |

I motori di analisi sono gli stessi in entrambe: statistiche, scoring, generatori,
backtest walk-forward, Monte Carlo, machine learning. La versione web è il porting in
JavaScript di quella Swift, ed è quella **verificata eseguendola davvero** (vedi sotto).

L'app è progettata come uno strumento di *data analysis*: importa uno storico,
lo descrive, cerca pattern, genera combinazioni con un **indice statistico** e — questa
è la parte che la distingue — **misura onestamente se quell'indice serva a qualcosa**,
confrontandolo con la pura casualità tramite backtest walk-forward, simulazioni Monte
Carlo e test di significatività. Quando non emerge alcun vantaggio, l'app lo scrive:
«Nessun vantaggio predittivo dimostrato».

---

## Web app: installarla sull'iPhone

Una volta attivate le GitHub Pages del repository (Settings → Pages → branch, cartella
`/docs`), l'app è raggiungibile a un indirizzo `https://<utente>.github.io/lotto/`.

Sull'iPhone: aprilo in **Safari** → tasto Condividi → **Aggiungi a Home**. L'icona che
compare avvia l'app a schermo intero, senza le barre del browser. Dopo la prima
apertura funziona anche **senza connessione**: il service worker tiene in cache tutto
il codice e i dati stanno in IndexedDB, sul telefono.

Per provarla in locale basta un server statico qualsiasi:

```bash
cd docs && python3 -m http.server 8000
```

Nessuna dipendenza, nessun passo di build, nessuna libreria esterna: HTML, CSS e
JavaScript scritti a mano, grafici in SVG puro. I calcoli pesanti girano in un
**Web Worker**, così l'interfaccia resta reattiva anche durante un Monte Carlo da un
milione di estrazioni.

## App iOS nativa: aprire il progetto

```bash
open LottoAIAnalyzer/LottoAIAnalyzer.xcodeproj
```

Requisiti: **Xcode 16** o successivo, **iOS 17.0+**. Nessuna dipendenza esterna:
tutto (statistica, machine learning, lettura/scrittura ZIP per l'Excel, export PDF)
è implementato con i soli framework di sistema.

Il progetto usa i gruppi sincronizzati con il file system di Xcode 16: aggiungere un
file nella cartella `LottoAIAnalyzer/` lo include automaticamente nel target.

Per eseguire i test: `⌘U` in Xcode, oppure

```bash
xcodebuild test -project LottoAIAnalyzer/LottoAIAnalyzer.xcodeproj \
  -scheme LottoAIAnalyzer -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Primo avvio

Lo **storico ufficiale è già incluso** nella web app: in **Dati** un tocco su *Carica lo
storico ufficiale* riempie l'archivio, senza doversi procurare nulla.

| Gioco | Estrazioni | Periodo | Fonte |
|---|---|---|---|
| Lotto | 77.000, su tutte e 11 le ruote | 7 gennaio 1939 → 29 agosto 2026 | archivio storico ufficiale del Lotto |
| SuperEnalotto | 4.258 concorsi, con Jolly e SuperStar | 3 dicembre 1997 (concorso n. 1) → 29 agosto 2026 | archivio ufficiale Sisal dal 2009, più un archivio pubblico per gli anni precedenti |

Quello ufficiale del SuperEnalotto non pubblica gli anni prima del 2009: per il periodo
1997-2008 si usa un archivio pubblico, **confrontato riga per riga con quello ufficiale
sui 470 concorsi in comune** — combinazione, Jolly, SuperStar e numero di concorso, zero
discordanze. Se il confronto fallisse, lo script si fermerebbe senza riscrivere il file.

I file stanno in [`docs/data/`](docs/data) come normali CSV, con la provenienza
documentata nel [README di quella cartella](docs/data/README.md), e si rigenerano con
gli script in [`tools/`](tools). Il caricamento avviene sul telefono: i dati non escono
dal dispositivo.

In alternativa, sempre da **Dati**, puoi:

1. **Importare un file** CSV, JSON o XLSX (vedi
   [`Resources/FORMATO.md`](LottoAIAnalyzer/LottoAIAnalyzer/Resources/FORMATO.md)
   per le colonne riconosciute e un file modello);
2. **Configurare una sorgente remota** — un indirizzo che hai il diritto di usare
   (API ufficiale, portale open data, un tuo export). Nessuna sorgente è preconfigurata;
3. **Caricare dati di esempio**: estrazioni **simulate**, generate localmente con un
   seme fisso, per esplorare l'interfaccia. Sono etichettate come tali ovunque.

L'app iOS nativa, che non ha i file inclusi, parte invece con l'archivio vuoto e usa i
punti 1-3.

---

## Un pattern vero, trovato nell'archivio

Con 77.000 estrazioni la potenza statistica è enorme: una distorsione anche piccola
lascia una traccia. [`tools/cerca_pattern.py`](tools/cerca_pattern.py) esegue **48 test
decisi in anticipo** — uniformità dei 90 numeri per ruota e per epoca, ripetizioni
dall'estrazione precedente, autocorrelazione a distanza 1-5, giorno della settimana,
proprietà aggregate, i 4.005 ambi — e chiude con la correzione di Benjamini-Hochberg,
perché facendo decine di test qualcuno risulta «significativo» per forza.

**Cinque test sopravvivono, e descrivono tutti lo stesso effetto.**

> Fra il **1970 e il 1999** i numeri alti uscivano più dei bassi.

| Periodo | Estrazioni | Media dei numeri estratti | z |
|---|---|---|---|
| 1939-1969 | 15.981 | 45,614 | +1,27 |
| **1970-1999** | **17.120** | **46,180** | **+7,83** |
| 2000-2026 | 43.899 | 45,492 | −0,14 |

Se le estrazioni fossero uniformi la media varrebbe 45,500 sempre. Nel trentennio
centrale è quasi otto deviazioni standard sopra: p ≈ 5·10⁻¹⁵.

**Le verifiche che lo rendono credibile:**

- **Replica interna** — separando gli anni pari (z = +5,19) dai dispari (z = +5,88),
  l'effetto compare in entrambe le metà.
- **Tutte le ruote** — 10 su 10 hanno media sopra 45,5 in quel periodo (Cagliari +7,65,
  Roma +6,07). La probabilità che dieci monete diano tutte testa è 1 su 1.024.
- **È liscio, non a macchie** — la correlazione fra il valore di un numero e la sua
  frequenza è r = **+0,691** nel 1970-1999 e **−0,016** nel 2000-2026. Gli ultimi nove
  numeri escono il 5,9% più dell'atteso, i primi nove il 3,6% meno.
- **Controlli negativi puliti** — prima del 1970 e dopo il 1999 non c'è niente.
- **Ha una firma fisica** — l'effetto è fortissimo sul **primo** numero estratto
  (z = +6,76) e si spegne verso il quinto (+1,59); nel periodo pulito tutte le posizioni
  sono piatte. Un errore nei dati non avrebbe motivo di seguire l'ordine di uscita.

Che cosa lo abbia causato, i dati non lo dicono: è coerente con un'urna o un lotto di
palline leggermente sbilanciati, in un'epoca di estrazioni meccaniche, ma è
un'ipotesi, non una conclusione.

### E adesso la parte scomoda

Il pattern è reale. Non serve a vincere.

Giocando sempre **86-87-88-89-90** — regola fissa, decisa senza guardare i dati — si
sarebbero centrati 0,2943 numeri per estrazione nel 1970-1999 contro 0,2778 attesi:
**+6,0%** (z = +4,33). Fuori da quel periodo, +0,6% e +0,5%: niente.

E scegliendo i numeri su un periodo per giocarli sul successivo — l'unico modo onesto,
perché il futuro non si conosce — il vantaggio evapora:

| Numeri scelti su | Giocati su | Vantaggio |
|---|---|---|
| 1970-1984 | 1985-1999 | +0,3% |
| 1970-1989 | 1990-1999 | +4,6% |
| 1970-1999 | 2000-2026 | +0,9% |

Il Lotto restituisce ai giocatori circa il 60-70% del giocato: per andare in pari
servirebbe un vantaggio fra il **43% e il 67%**. Il pattern più forte in 87 anni di
storia ne vale il 6%, in un'epoca finita da un quarto di secolo. Per distinguere un
vantaggio del 6% dal caso, giocando, servirebbero circa 2.000 estrazioni: tredici anni
a tre estrazioni a settimana.

Gli altri 43 test non hanno trovato nulla. L'ambo più anomalo su 4.005 (il 45-49, uscito
133 volte contro 192 attese) ha p = 0,072 una volta corretto per il fatto di essere il
massimo di una lista lunga — cioè è esattamente quello che ci si aspetta di trovare
guardando 4.005 coppie.

La scheda **Trova pattern** dell'app racconta tutto questo, ultima parte compresa.

---

## TimesFM: un modello di Google messo alla prova sulle estrazioni

[TimesFM 3.0](https://github.com/google-research/timesfm) è il modello *foundation* per
serie temporali di Google Research: oltre un miliardo di parametri, primo in classifica
su fev-bench, TIME Benchmark e GIFT-Eval. In **AI Analyst** compare fra i modelli
selezionabili e mostra i numeri che prevede per la prossima estrazione di ogni ruota.

Accanto ai numeri, sempre, c'è la misura di quanto valgono — perché senza quella i
numeri direbbero una cosa che i dati smentiscono.

**Come è stato messo alla prova.** Prova walk-forward su 150 estrazioni della ruota di
Bari: a ogni passo il modello vede soltanto le estrazioni precedenti. Le estrazioni gli
sono state date in tre codifiche diverse, per non penalizzarlo con una
rappresentazione infelice — serie binaria di uscita, ritardo, frequenza mobile — tutte e
90 le serie insieme, in modalità multivariata. Si prendono i 5 numeri col punteggio più
alto e si contano i centri.

| | Centri per estrazione | AUC | p |
|---|---|---|---|
| **Controllo** — estrazioni sintetiche regolari | **4,85** su 5 | **0,983** | — |
| TimesFM, codifica binaria — estrazioni vere | 0,253 | 0,491 | 0,55 |
| TimesFM, codifica ritardo — estrazioni vere | 0,313 | 0,523 | 0,38 |
| TimesFM, codifica frequenza — estrazioni vere | 0,320 | 0,520 | 0,30 |
| Baseline: 5 numeri a caso | 0,180 | — | — |
| Attesa teorica (5 su 90) | 0,278 | 0,500 | — |

**Il controllo positivo è la parte importante.** Sulle estrazioni *inventate e
volutamente regolari* TimesFM azzecca 4,85 numeri su 5, con AUC 0,983: la procedura
funziona, il modello funziona, le metriche funzionano. Quando c'è qualcosa da prevedere,
lo prevede. Sulle estrazioni vere tutte e tre le codifiche restano dentro il rumore
attorno allo 0,278 atteso dal caso, e l'AUC resta attaccata allo 0,500.

Senza quel controllo, «AUC 0,50» non si distinguerebbe da un bug.

Un dettaglio che vale la pena notare: la baseline dei 5 numeri a caso è finita a 0,180
centri, cioè *sotto* l'attesa, con p = 0,017. Su 150 estrazioni una deviazione
«significativa» capita per puro caso — è esattamente il motivo per cui un singolo
p < 0,05 non dimostra niente, in nessuna direzione.

### E se gli si dà un pattern che c'è davvero?

Il trentennio 1970-1999 offre un banco di prova che non capita spesso: **dati reali con
dentro un pattern vero e verificato.** TimesFM se ne accorge?

La domanda si misura meglio guardando non i 5 numeri scelti, ma tutti e 90 i punteggi:
se il modello capisse che i numeri alti escono di più, il punteggio che assegna
crescerebbe col valore del numero. Ho fatto girare la stessa procedura su tre
condizioni — Cagliari, la ruota con la distorsione più forte.

| Codifica | Estrazioni casuali<br>*nessun pattern* | Cagliari 1970-99<br>***pattern vero*** | Cagliari 2000-26<br>*nessun pattern* |
|---|---|---|---|
| binaria | +0,013 (z +1,38) | +0,015 (z +1,98) | −0,036 (z −3,99) |
| ritardo | +0,020 (z +3,01) | +0,056 (z +6,33) | −0,009 (z −1,33) |
| frequenza | **+0,049 (z +10,07)** | +0,044 (z +4,18) | +0,005 (z +0,62) |

Guardando solo la colonna centrale si griderebbe alla scoperta: z = +6,33.

**La prima colonna smonta tutto.** Su estrazioni sintetiche perfettamente casuali, dove
per costruzione non c'è assolutamente niente, la codifica «frequenza» produce già
+0,049 con z = +10,07 — *più* di quanto produca sull'epoca col pattern vero. Non è una
scoperta: è una tendenza del modello a dare punteggi più alti ai numeri più alti,
indipendentemente dai dati. E il z nominale è gonfiato perché finestre consecutive da
512 estrazioni si sovrappongono quasi del tutto, quindi i 150 passi non sono
indipendenti: lo si legge nella colonna di destra, dove un −3,99 compare su dati che
non hanno alcun pattern.

Nessuna codifica mostra sull'epoca distorta un segnale che il rumore puro non produca
già da solo. **TimesFM non si accorge del pattern**, nemmeno di uno reale, verificato e
grande otto deviazioni standard in aggregato — perché su una singola estrazione quel
pattern vale il 6%, e il 6% dentro l'incertezza di 512 estrazioni non si vede.

Senza il controllo negativo avrei riportato una scoperta. È lo stesso motivo per cui la
prova sui dati veri ha un controllo positivo: **una misura senza i suoi controlli non
significa niente**, e vale sia quando dice di no sia quando dice di sì.

I tre script (`tools/timesfm_lotto.py`, `tools/timesfm_previsione.py`,
`tools/cerca_pattern.py`) rendono tutto rieseguibile. Il modello gira in Python su PyTorch e non può girare nel browser: le
previsioni sono calcolate una volta e distribuite come file, ferme all'ultima estrazione
indicata nel file stesso.

---

## Architettura

```
SwiftUI  →  ViewModel  →  Analytics Engine  →  Statistics Engine
                                ↓                     ↓
                            ML Engine    →     Database (SwiftData)
                                                      ↑
                                          Data Import / API
```

| Cartella | Contenuto |
|---|---|
| `Models/` | `Draw`, `DrawRecord`, ruote, giochi, periodi, pesi, avvertenze |
| `Persistence/` | `DatabaseService` (unico punto di accesso a SwiftData), dati di esempio |
| `DataImport/` | CSV, JSON, XLSX (con lettore ZIP), sorgenti remote, aggiornamento automatico |
| `Analytics/` | statistiche, scoring, ambi, terni, cinquine, multi-ruota, Monte Carlo, backtest, pattern, validazione |
| `ML/` | feature, k-means, regressione logistica, Random Forest, gradient boosting, modello bayesiano, aggancio Core ML |
| `ViewModels/` | stato osservabile delle schermate |
| `Views/` | dashboard, analisi, generatori, laboratorio, dati, impostazioni |
| `Report/` | export PDF / CSV / XLSX (con scrittore ZIP) |
| `Design/` | tema e componenti riusabili |

Regola di fondo: **i motori non conoscono SwiftData né SwiftUI**. Lavorano su array di
`DrawRecord` (valori `Sendable`), quindi girano fuori dal main actor e sono testabili
senza database.

---

## Che cosa calcola

**Per numero** — uscite, frequenza osservata contro attesa, ritardo attuale, ritardo
medio e massimo, rapporto ritardo/massimo, percentile, frequenza recente, trend,
volatilità, forza di co-occorrenza. Aggregazioni per anno, mese, ruota, decina, unità.

**Per combinazione** — co-occorrenze di coppie e terne (conteggi, ritardi e rapporto
osservato/atteso), somma, parità, fascia 1–45 / 46–90, distribuzione fra decine,
numeri consecutivi, distanza media.

**Statistical Number Score** — l'indice statistico 0–100. Ogni criterio (frequenza,
recenza, ritardo, trend, co-occorrenza, stabilità) è normalizzato in percentile
rispetto agli altri 89 numeri, poi combinato con pesi configurabili in Impostazioni.
🟢 80–100 · 🟡 50–79 · 🔴 0–49.

> È un *indice statistico*: descrive il comportamento passato di un numero.
> Non è, e non viene mai presentato come, una probabilità di uscita.

---

## Generatori

| Funzione | Cosa fa |
|---|---|
| **Ambi** | valuta tutte le 4.005 coppie 1–90 e mostra le prime 10 con il «Perché?» |
| **Terni** | esplora le combinazioni di 3 numeri (117.480 in enumerazione completa, oppure le migliori 45 per rapidità) |
| **Cinquina AI** | 5 numeri (6 per il SuperEnalotto) in modalità Conservativa, Bilanciata, Diversificata, Random statistica |
| **Multi-ruota** | numeri, ambi, terni e cinquina con segnali coerenti su più delle 11 ruote |
| **🔮 Genera combinazione** | procedura guidata gioco → strategia → periodo, con 5 combinazioni motivate |

Le C(90,5) = 43.949.268 cinquine non sono enumerabili: il generatore usa un
campionamento pesato dagli indici statistici, filtrato dai vincoli storici osservati
(somma, parità, fascia, decine, consecutivi) e affinato da una ricerca locale. Con lo
stesso seme produce sempre lo stesso risultato.

---

## Verifica: la parte seria

**Backtest walk-forward.** «Se avessi usato questo algoritmo negli ultimi 12 mesi, cosa
sarebbe successo?» A ogni estrazione simulata il motore ricostruisce le statistiche
applicando un limite temporale **stretto** (`AnalysisFilter.cutoffDate`): entrano solo le
estrazioni con data *precedente* a quella simulata. Non esiste un percorso che permetta
ai dati futuri di raggiungere il calcolo — ed è verificato da un test che confronta le
statistiche con cutoff e quelle del solo prefisso storico, numero per numero.

Il backtest riporta combinazioni giocate, estrazioni, ambi/terni/cinquine centrati,
costo teorico, vincite teoriche e ROI teorico, sempre affiancati da una **baseline
casuale** che gioca lo stesso numero di combinazioni con numeri estratti a caso.

**Sistema di validazione.** Prima di considerare "migliore" un algoritmo l'app esegue
backtest, walk-forward su 4 finestre consecutive, confronto con la baseline (test z su
due proporzioni), Monte Carlo e test statistici. Il verdetto è conservativo: dichiara un
vantaggio solo se *tutti* i controlli lo confermano; altrimenti stampa
**«Nessun vantaggio predittivo dimostrato»**.

**Monte Carlo.** 100.000 / 500.000 / 1.000.000 estrazioni simulate, confrontate con lo
storico su frequenze, somme, parità, decine e ritardi, con chi quadro e test binomiali.

**Trova pattern.** Cerca ricorrenze, coppie anomale, cluster e stagionalità — e per
ciascuna dice se è statisticamente significativa o compatibile con il caso, ricordando
che testando 90 numeri e 4.005 coppie qualche "scoperta" arriva per pura molteplicità
dei test.

**Machine learning** (sperimentale). k-means, regressione logistica, Random Forest,
**gradient boosting**, modello bayesiano, rilevazione anomalie — tutto in Swift, senza
dipendenze. XGBoost e LightGBM non esistono come librerie su iOS: il `GradientBoostingClassifier`
implementa la stessa famiglia di algoritmi (alberi additivi, passo di Newton di Friedman nelle
foglie, learning rate, campionamento di righe e colonne).

Lo split fra addestramento e test è temporale. La metrica riportata è l'AUC: su un processo
casuale resta attorno a 0,500, ed è esattamente questo il risultato che l'app mostra invece di
nasconderlo. Perché quel numero significhi qualcosa, i test verificano anche il contrario — che
sugli stessi modelli, con un segnale vero nei dati, l'AUC salga oltre 0,90: senza questo controllo
un 0,500 potrebbe voler dire semplicemente che il modello è rotto.

`CoreMLScorer` è il punto di innesto per un modello addestrato altrove (scikit-learn, XGBoost)
e convertito con `coremltools`: se un `.mlmodelc` è presente nel bundle viene usato al posto dei
modelli interni, e passa comunque dalla stessa valutazione temporale con baseline.

---

## Come è stata verificata

La versione web è stata **eseguita davvero** in Chromium durante lo sviluppo, non solo
letta. Due suite end-to-end guidano l'app come farebbe una persona — accettano
l'avvertenza, importano lo storico, aprono ogni schermata, generano combinazioni,
lanciano backtest, Monte Carlo e modelli — e verificano che non compaia alcun errore
JavaScript. Hanno trovato due difetti reali che una semplice rilettura del codice non
avrebbe rivelato: le schermate raggiunte dalla barra inferiore perdevano lo stato a
ogni aggiornamento, e la barra spariva nelle schermate di dettaglio.

Le funzioni matematiche sono state controllate contro valori noti: chi quadro ai punti
critici tabellari, `erfc` e la normale standard a sei decimali, CRC-32 sul vettore di
prova standard, il round-trip dell'indice su tutte le 4.005 coppie. La prima stesura di
`erfc` era sbagliata (dava 0,141 dove serviva 0,500) ed è stata riscritta riusando la
gamma incompleta già verificata.

Il gradient boosting è controllato **su entrambi i lati**: AUC oltre 0,99 quando nei
dati c'è un segnale vero, e 0,500 su etichette casuali con lo stesso sbilanciamento del
problema reale. Senza il primo controllo, un'AUC di 0,500 sui dati del Lotto non
distinguerebbe l'assenza di segnale da un modello rotto.

Sui dati simulati inclusi nell'app — che sono casuali per costruzione — il modello
riporta un'AUC di circa 0,49 e il verdetto «Nessun vantaggio predittivo dimostrato».
È il risultato corretto, ed è quello che l'app mostra.

---

## Privacy

Tutto gira sul dispositivo. Nessuna registrazione, nessun account, nessun dato personale
raccolto o inviato. Le estrazioni stanno in un archivio locale (SwiftData sull'app nativa,
IndexedDB nella web app), separato dalle preferenze. Le uniche connessioni di rete sono
quelle verso le sorgenti configurate dall'utente.

---

## Principio di fondo

L'app non dice mai «questo numero uscirà», «questa cinquina ha maggiore probabilità
matematica» o «abbiamo previsto l'estrazione». Dice: «questo numero presenta un'elevata
frequenza storica», «questa coppia ha una ricorrenza superiore alla media», «questa
combinazione ha ottenuto un indice statistico elevato», «il modello non dimostra capacità
predittiva oltre la casualità».

Il gioco può causare dipendenza patologica. Gioca solo se maggiorenne e con moderazione.
