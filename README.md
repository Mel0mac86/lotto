# Lotto AI Analyzer

Applicazione iPhone (SwiftUI + SwiftData) per l'**analisi statistica** degli estratti
del Lotto italiano e del SuperEnalotto.

> **Le estrazioni sono casuali. Le analisi statistiche degli estratti passati non
> modificano la probabilità matematica di vincita. Le combinazioni generate sono
> suggerimenti statistici e non previsioni certe.**

L'app è progettata come uno strumento di *data analysis*: importa uno storico,
lo descrive, cerca pattern, genera combinazioni con un **indice statistico** e — questa
è la parte che la distingue — **misura onestamente se quell'indice serva a qualcosa**,
confrontandolo con la pura casualità tramite backtest walk-forward, simulazioni Monte
Carlo e test di significatività. Quando non emerge alcun vantaggio, l'app lo scrive:
«Nessun vantaggio predittivo dimostrato».

---

## Come aprire il progetto

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

L'archivio parte vuoto. In **Dati** puoi:

1. **Importare un file** CSV, JSON o XLSX (vedi
   [`Resources/FORMATO.md`](LottoAIAnalyzer/LottoAIAnalyzer/Resources/FORMATO.md)
   per le colonne riconosciute e un file modello);
2. **Configurare una sorgente remota** — un indirizzo che hai il diritto di usare
   (API ufficiale, portale open data, un tuo export). Nessuna sorgente è preconfigurata;
3. **Caricare dati di esempio**: estrazioni **simulate**, generate localmente con un
   seme fisso, per esplorare l'interfaccia. Sono etichettate come tali ovunque.

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
| `ML/` | feature, k-means, regressione logistica, alberi/Random Forest, modello bayesiano |
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
modello bayesiano, rilevazione anomalie. Lo split fra addestramento e test è temporale.
La metrica riportata è l'AUC: su un processo casuale resta attorno a 0,500, ed è esattamente
questo il risultato che l'app mostra invece di nasconderlo.

---

## Privacy

Tutto gira sul dispositivo. Nessuna registrazione, nessun account, nessun dato personale
raccolto o inviato. Le estrazioni stanno in un database locale, separato dalle preferenze.
Le uniche connessioni di rete sono quelle verso le sorgenti configurate dall'utente.

---

## Principio di fondo

L'app non dice mai «questo numero uscirà», «questa cinquina ha maggiore probabilità
matematica» o «abbiamo previsto l'estrazione». Dice: «questo numero presenta un'elevata
frequenza storica», «questa coppia ha una ricorrenza superiore alla media», «questa
combinazione ha ottenuto un indice statistico elevato», «il modello non dimostra capacità
predittiva oltre la casualità».

Il gioco può causare dipendenza patologica. Gioca solo se maggiorenne e con moderazione.
