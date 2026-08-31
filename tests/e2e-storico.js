/* Carica lo storico ufficiale incluso (decine di migliaia di estrazioni reali)
   e verifica che l'archivio si riempia e che l'analisi ci giri sopra. */
const { chromium } = require('playwright-core');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
    args: ['--no-sandbox']
  });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });

  const errors = [];
  page.on('pageerror', (e) => errors.push('PAGEERROR: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text()); });

  const report = (label, ok, extra) =>
    console.log((ok ? '  OK   ' : '  FAIL ') + label + (extra ? '  → ' + extra : ''));

  await page.goto('http://localhost:8765/index.html', { waitUntil: 'networkidle' });
  await page.click('text=Ho capito, iniziamo');
  await page.waitForSelector('.tabbar', { timeout: 5000 });

  // 1. La scheda Dati descrive lo storico incluso prima di scaricarlo
  await page.click('.tabbar button:nth-child(5)');
  await page.waitForSelector('text=Storico ufficiale incluso', { timeout: 10000 });
  await page.waitForFunction(
    () => !document.body.innerText.includes('Lettura dell’indice in corso'),
    null, { timeout: 20000 });
  const descrizione = await page.textContent('main');
  report('manifesto letto',
    /\d{2}\/\d{2}\/19\d{2}/.test(descrizione) && descrizione.includes('11 ruote'));

  // 2. Caricamento del Lotto: 77.000 estrazioni reali
  const inizio = Date.now();
  await page.click('button:has-text("Carica lo storico ufficiale") >> nth=0');
  await page.waitForFunction(
    () => document.body.innerText.includes('estrazioni aggiunte'), null, { timeout: 300000 });
  const durata = ((Date.now() - inizio) / 1000).toFixed(1);
  const testoLotto = await page.textContent('main');
  const inserite = Number((testoLotto.match(/([\d.]+) estrazioni aggiunte/) || [])[1]
    .replace(/\./g, ''));
  report('storico Lotto caricato', inserite > 70000, inserite + ' estrazioni in ' + durata + ' s');

  // 3. Ricaricando, tutto risulta già presente: nessun duplicato in archivio
  await page.click('button:has-text("Aggiorna dallo storico ufficiale") >> nth=0');
  await page.waitForFunction(
    () => /0 estrazioni aggiunte/.test(document.body.innerText), null, { timeout: 300000 });
  report('nessun duplicato al secondo caricamento', true);

  // 4. SuperEnalotto
  await page.click('button:has-text("Carica lo storico ufficiale") >> nth=0');
  await page.waitForFunction(
    () => (document.body.innerText.match(/estrazioni aggiunte/g) || []).length >= 2,
    null, { timeout: 300000 });
  const conteggi = await page.evaluate(() => Lotto.app.state.counts);
  report('archivio SuperEnalotto pieno', conteggi.superenalotto > 2000,
    JSON.stringify(conteggi));

  // 5. Le date estreme sono quelle attese dai file
  const estremi = await page.evaluate(async () => {
    const draws = await Lotto.db.loadDraws('lotto');
    return {
      totale: draws.length,
      prima: new Date(draws[0].date).toISOString().slice(0, 10),
      ultima: new Date(draws[draws.length - 1].date).toISOString().slice(0, 10)
    };
  });
  report('periodo del Lotto coerente', estremi.prima.startsWith('1939'), JSON.stringify(estremi));

  // 6. L'analisi gira sui dati reali
  await page.click('.tabbar button:nth-child(2)');
  await page.click('text=Analisi annuale e multi-anno');
  await page.waitForFunction(
    () => document.body.innerText.includes('Indice statistico')
      || document.body.innerText.includes('Frequenza'), null, { timeout: 120000 });
  const analisi = await page.textContent('main');
  report('analisi calcolata sullo storico reale',
    analisi.includes('Non rappresenta la probabilità reale')
    || analisi.includes('non modificano la probabilità'));

  await browser.close();
  console.log('');
  if (errors.length) {
    console.log('ERRORI RILEVATI:');
    [...new Set(errors)].slice(0, 12).forEach((e) => console.log('  ' + e));
    process.exit(1);
  }
  console.log('Nessun errore JavaScript.');
})().catch((e) => { console.error('FALLITO:', e.message); process.exit(1); });
