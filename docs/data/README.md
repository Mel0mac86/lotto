# Storico delle estrazioni incluso nell'app

Questi file sono una **copia locale di archivi pubblici** delle estrazioni. Servono
perché l'app sia utile al primo avvio, senza che chi la usa debba procurarsi i dati.
Sono normali file CSV: si possono leggere, controllare e reimportare a mano.

Vengono ricostruiti dagli script in [`tools/`](../../tools), che scaricano gli archivi
originali e li convertono. Il manifesto `manifest.json` è generato da
`tools/build_manifest.py` e descrive quello che c'è dentro.

## `lotto-storico.csv`

    data;ruota;numero1;numero2;numero3;numero4;numero5
    19390107;BA;58;22;47;49;69

- **Origine:** archivio storico ufficiale del Lotto pubblicato dal concessionario
  (`https://www.brightstarlottery.it/STORICO_ESTRAZIONI_LOTTO/storico.zip`).
- **Copertura:** dal 7 gennaio 1939 a oggi, tutte e 11 le ruote.
- Le ruote usano i codici a due lettere dell'archivio ufficiale
  (`BA CA FI GE MI NA PA RM TO VE` più `RN` per la Nazionale), che l'app riconosce.

## `superenalotto-storico.csv`

    data;concorso;numero1;numero2;numero3;numero4;numero5;numero6;jolly;superstar
    19971203;1;22;41;44;56;70;80;61;

- **Origine, dal 2009:** archivio estrazioni ufficiale Sisal
  (`https://www.superenalotto.it/archivio-estrazioni`), che però non pubblica gli anni
  precedenti.
- **Origine, 1997-2008:** archivio di `estrazionilottooggi.it`, l'unico consultabile
  che parte dalla prima estrazione del 3 dicembre 1997.
- **Verifica:** le due fonti vengono confrontate riga per riga sugli anni in cui si
  sovrappongono (combinazione, Jolly, SuperStar e numero di concorso). Se emerge anche
  una sola discordanza lo script si ferma e il file non viene riscritto: senza quella
  verifica la parte 1997-2008 non sarebbe controllabile.
- Il SuperStar è stato introdotto nel 2006: prima di allora la colonna è vuota.

## Nota

Le estrazioni sono fatti pubblici, ripubblicati qui per uso statistico e personale.
Le fonti originali sono citate qui sopra e nella schermata Dati dell'app. Per le
estrazioni successive a questa copia l'app permette di importare un file o di
configurare una sorgente remota.
