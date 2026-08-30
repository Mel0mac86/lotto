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

  // 1. Schermata di benvenuto con l'avvertenza
  const welcome = await page.textContent('#app');
  report('schermata iniziale con avvertenza',
    welcome.includes('Le estrazioni sono casuali') && welcome.includes('Non prevede'));

  await page.click('text=Ho capito, iniziamo');
  await page.waitForSelector('.tabbar', { timeout: 5000 });
  report('dashboard caricata', (await page.$$('.tile')).length > 8,
    (await page.$$('.tile')).length + ' riquadri');

  // 2. Caricamento dati di esempio
  await page.click('.tabbar button:nth-child(5)');
  await page.waitForSelector('text=Carica dati di esempio simulati');
  await page.click('text=Carica dati di esempio simulati');
  await page.waitForFunction(
    () => document.body.innerText.includes('estrazioni importate'), null, { timeout: 60000 });
  const dataText = await page.textContent('main');
  const inserted = (dataText.match(/(\d+) estrazioni importate/) || [])[1];
  report('dati di esempio importati', Number(inserted) > 1000, inserted + ' estrazioni');

  // 3. Analisi
  await page.click('.tabbar button:nth-child(2)');
  await page.waitForSelector('text=Analisi annuale e multi-anno');
  await page.click('text=Analisi annuale e multi-anno');
  await page.waitForFunction(
    () => document.body.innerText.includes('Periodo analizzato'), null, { timeout: 60000 });
  const analysis = await page.textContent('main');
  report('analisi calcolata',
    analysis.includes('Frequenza dei numeri') && analysis.includes('Tabella completa'));
  report('grafici disegnati', (await page.$$('main svg')).length >= 4,
    (await page.$$('main svg')).length + ' grafici');

  // 4. Dettaglio numero
  await page.click('.rows .row.tappable >> nth=1');
  await page.waitForFunction(
    () => document.body.innerText.includes('Indicatori'), null, { timeout: 30000 });
  report('dettaglio numero',
    (await page.textContent('main')).includes('Lettura in linguaggio naturale'));
  await page.click('.topbar .back');
  await page.click('.topbar .back');

  // 5. Generatore guidato
  await page.click('.tabbar button:nth-child(3)');
  await page.waitForSelector('text=🔮 Genera combinazione');
  await page.click('button:has-text("🔮 Genera combinazione")');
  await page.waitForFunction(
    () => document.body.innerText.includes('Impostazioni usate'), null, { timeout: 90000 });
  const balls = await page.$$eval('main .ball', (nodes) => nodes.map((n) => n.textContent));
  report('combinazioni generate', balls.length >= 25, balls.length + ' numeri mostrati');
  report('numeri validi 1–90', balls.every((b) => Number(b) >= 1 && Number(b) <= 90));

  // 6. Pagina risultato e salvataggio
  await page.click('button:has-text("Motivazioni") >> nth=0');
  await page.waitForFunction(
    () => document.body.innerText.includes('Statistical Score'), null, { timeout: 30000 });
  const result = await page.textContent('main');
  report('pagina risultato completa',
    result.includes('Distribuzione') && result.includes('In sintesi')
    && result.includes('Non rappresenta la probabilità reale'));
  // Il toast precedente potrebbe essere ancora a schermo: si attende il testo atteso.
  await page.evaluate(() => { document.getElementById('toast-host').innerHTML = ''; });
  await page.click('button:has-text("🔖 Salva combinazione")');
  await page.waitForFunction(
    () => document.getElementById('toast-host').innerText.trim().length > 0,
    null, { timeout: 15000 });
  const toastText = await page.textContent('#toast-host');
  report('salvataggio combinazione', toastText.includes('salvata'), toastText);

  // 7. Confronto: la combinazione salvata deve comparire
  await page.click('.topbar .back');
  await page.click('.tabbar button:nth-child(4)');
  await page.click('text=Confronto combinazioni');
  await page.waitForFunction(
    () => document.body.innerText.includes('Combinazioni salvate')
      || document.body.innerText.includes('Nessuna combinazione salvata'), null, { timeout: 20000 });
  report('confronto elenca il salvataggio',
    (await page.textContent('main')).includes('Combinazioni salvate'));

  await browser.close();
  console.log('');
  if (errors.length) {
    console.log('ERRORI RILEVATI:');
    [...new Set(errors)].slice(0, 12).forEach((e) => console.log('  ' + e));
    process.exit(1);
  }
  console.log('Nessun errore JavaScript.');
})().catch((e) => { console.error('FALLITO:', e.message); process.exit(1); });
