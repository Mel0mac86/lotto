/* La schermata TimesFM: verifica che i numeri previsti non compaiano mai da
   soli, ma sempre accanto alla misura di quanto valgono e al controllo
   positivo che rende quella misura leggibile. */
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

  // Serve uno storico in archivio perché la schermata dei modelli si apra.
  await page.click('.tabbar button:nth-child(5)');
  await page.waitForSelector('text=Storico ufficiale incluso', { timeout: 10000 });
  await page.waitForFunction(
    () => !document.body.innerText.includes('Lettura dell’indice in corso'),
    null, { timeout: 20000 });
  await page.click('button:has-text("Carica lo storico ufficiale") >> nth=0');
  await page.waitForFunction(
    () => document.body.innerText.includes('estrazioni aggiunte'), null, { timeout: 300000 });

  await page.click('.tabbar button:nth-child(4)');
  await page.click('text=AI Analyst');
  await page.waitForSelector('select', { timeout: 15000 });

  const models = await page.$$eval('select', (selects) =>
    selects.map((select) => Array.from(select.options).map((option) => option.text)));
  report('TimesFM fra i modelli', JSON.stringify(models).includes('TimesFM'));

  await page.selectOption('select >> nth=-1', { label: 'TimesFM 3.0 (Google)' });
  await page.click('button:has-text("Esegui")');
  await page.waitForFunction(
    () => document.body.innerText.includes('Quanto vale questa previsione'),
    null, { timeout: 30000 });

  const text = await page.textContent('main');
  report('previsione mostrata', text.includes('Previsione per'));
  report('cinquina prevista', (await page.$$('.ball')).length >= 5);
  report('misura accanto alla previsione',
    text.includes('Centri per estrazione') && text.includes('AUC'));
  report('confronto con il caso', text.includes('Attesi dal caso'));
  report('controllo positivo', text.includes('lo stesso modello su dati prevedibili'));
  report('verdetto onesto', text.includes('Nessun vantaggio predittivo dimostrato'));

  await page.waitForFunction(
    () => document.body.innerText.includes('Il modello davanti a un pattern vero'),
    null, { timeout: 20000 });
  const withEras = await page.textContent('main');
  report('esperimento sulle epoche', withEras.includes('1970-1999'));
  report('controllo negativo presente', withEras.includes('nessun pattern'));

  await browser.close();
  console.log('');
  if (errors.length) {
    console.log('ERRORI RILEVATI:');
    [...new Set(errors)].slice(0, 12).forEach((e) => console.log('  ' + e));
    process.exit(1);
  }
  console.log('Nessun errore JavaScript.');
})().catch((e) => { console.error('FALLITO:', e.message); process.exit(1); });
