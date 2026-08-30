/* Dati di esempio SIMULATI.

   Servono solo a poter esplorare l'interfaccia prima di importare uno storico
   reale: sono estrazioni generate localmente con un seme fisso, non dati veri,
   e sono etichettate come tali ovunque compaiano. */
(function (root) {
  'use strict';

  const Lotto = root.Lotto = root.Lotto || {};

  /** 3 estrazioni a settimana per `years` anni, su tutte le ruote più il SuperEnalotto. */
  function generateSimulatedHistory(years) {
    const generator = new Lotto.SeededRandom(20260101);
    const records = [];
    const end = new Date();
    const start = new Date(end.getTime());
    start.setFullYear(start.getFullYear() - (years || 4));

    const current = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate(), 12));
    const endTime = Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate(), 12);

    while (current.getTime() <= endTime) {
      const weekday = current.getUTCDay();
      // Martedì (2), giovedì (4) e sabato (6).
      if (weekday === 2 || weekday === 4 || weekday === 6) {
        const date = current.getTime();
        Lotto.WHEEL_IDS.forEach((wheel) => {
          records.push(Lotto.makeDraw(date, 'lotto', wheel, generator.drawNumbers(5, 90)));
        });
        const numbers = generator.drawNumbers(6, 90);
        const extra = generator.drawNumbers(2, 90);
        records.push(Lotto.makeDraw(date, 'superenalotto', null, numbers, extra[0], extra[1]));
      }
      current.setUTCDate(current.getUTCDate() + 1);
    }
    return records;
  }

  Lotto.seed = { generateSimulatedHistory: generateSimulatedHistory };
})(typeof self !== 'undefined' ? self : this);
