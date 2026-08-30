# Test end-to-end della web app

Guidano l'app in Chromium come farebbe una persona e verificano che ogni schermata
produca i risultati attesi senza errori JavaScript.

## Come eseguirli

```bash
# 1. servi la web app
cd docs && python3 -m http.server 8765 &

# 2. installa il driver del browser
npm install playwright-core

# 3. esegui
node tests/e2e-base.js       # avvio, import, analisi, generazione, salvataggio
node tests/e2e-completo.js   # ambi, terni, multi-ruota, Monte Carlo, pattern, ML, backtest
```

Il percorso di Chromium è impostato nei file (`executablePath`): va adattato al proprio
sistema, oppure sostituito con `playwright` completo che scarica il browser da sé.

## Che cosa hanno trovato

Non sono decorativi: alla prima esecuzione hanno rivelato due difetti reali che una
rilettura del codice non aveva mostrato.

1. **Stato perso nelle schermate della barra inferiore.** `refresh()` ricreava la
   schermata da zero invece di ridisegnare quella esistente, azzerandone lo stato
   locale: l'importazione dei dati di esempio restava bloccata su «in corso».
2. **Barra di navigazione assente nelle schermate di dettaglio**, contro il
   comportamento abituale delle app iOS.
