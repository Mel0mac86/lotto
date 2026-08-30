# Formato dei file di importazione

`formato_importazione.csv` è un modello con le colonne riconosciute dall'app.

## Colonne

| Colonna | Obbligatoria | Note |
|---|---|---|
| `data` | sì | `gg/mm/aaaa`, `aaaa-mm-gg`, `gg-mm-aaaa`, ISO 8601 o numero seriale Excel |
| `gioco` | no | `lotto` o `superenalotto`; se assente si usa il gioco scelto nella schermata di import |
| `ruota` | sì per il Lotto | nome esteso (`Bari`) o sigla (`BA`); ignorata per il SuperEnalotto |
| `numero1` … `numero6` | sì | accettati anche `n1`…`n6`, `num1`…`num6`, `estratto1`… |
| `numeri` | alternativa | una sola colonna con i numeri separati da spazio, virgola, punto e virgola o trattino |
| `jolly` | no | solo SuperEnalotto |
| `superstar` | no | solo SuperEnalotto |

Il separatore (`;`, `,`, tabulazione o `|`) viene rilevato automaticamente dall'intestazione.
Le intestazioni sono confrontate senza distinzione fra maiuscole, minuscole e accenti.

## JSON

Sono accettati sia un array di oggetti sia un oggetto contenitore con una chiave
`draws`, `estrazioni`, `data`, `results`, `items` o `records`:

```json
[
  { "data": "2026-01-03", "ruota": "Bari", "numeri": [12, 27, 44, 61, 83] },
  { "data": "2026-01-03", "gioco": "superenalotto", "numeri": [7, 18, 29, 41, 56, 88], "jolly": 13, "superstar": 42 }
]
```

## Excel

I file `.xlsx` vengono letti direttamente (primo foglio, prima riga come intestazione).
I vecchi `.xls` binari non sono supportati: vanno convertiti in `.xlsx` o `.csv`.

## Deduplica

Ogni estrazione ha una chiave `gioco|ruota|data|numeri ordinati`. Le righe già presenti
vengono contate come duplicati e ignorate, quindi è sicuro reimportare lo stesso file.
