/* La scheda «Trova pattern» deve raccontare per intero il pattern trovato
   nell'archivio: l'effetto, dove agiva, e il fatto che non serva a vincere.
   È l'ultima parte quella che si perde per strada, quindi è quella che il
   test controlla con più insistenza. */
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

  await page.click('.tabbar button:nth-child(5)');
  await page.waitForFunction(
    () => !document.body.innerText.includes('Lettura dell’indice in corso'),
    null, { timeout: 20000 });
  await page.click('button:has-text("Carica lo storico ufficiale") >> nth=0');
  await page.waitForFunction(
    () => document.body.innerText.includes('estrazioni aggiunte'), null, { timeout: 300000 });

  await page.click('.tabbar button:nth-child(4)');
  await page.click('text=Trova pattern');
  await page.waitForFunction(
    () => document.body.innerText.includes('Un pattern vero, nello storico'),
    null, { timeout: 20000 });

  const text = await page.textContent('main');
  report('scoperta mostrata', text.includes('numeri alti uscivano più dei bassi'));
  report('epoche a confronto', text.includes('1939-1969') && text.includes('2000-2026'));
  report('meccanismo per posizione', text.includes('numero estratto'));
  report('vantaggio fuori campione', text.includes('giocati sul'));
  report('margine del banco dichiarato', text.includes('43%') && text.includes('67%'));
  report('molteplicità dichiarata', text.includes('48 test'));

  // La ricerca interattiva sul periodo scelto deve continuare a funzionare.
  await page.click('button:has-text("Trova pattern")');
  await page.waitForFunction(
    () => document.body.innerText.includes('Pattern esaminati'), null, { timeout: 60000 });
  report('ricerca interattiva', (await page.textContent('main')).includes('Pattern esaminati'));

  await browser.close();
  console.log('');
  if (errors.length) {
    console.log('ERRORI RILEVATI:');
    [...new Set(errors)].slice(0, 12).forEach((e) => console.log('  ' + e));
    process.exit(1);
  }
  console.log('Nessun errore JavaScript.');
})().catch((e) => { console.error('FALLITO:', e.message); process.exit(1); });
