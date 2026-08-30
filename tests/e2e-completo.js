const { chromium } = require('playwright-core');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push('PAGEERROR: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text()); });

  const report = (label, ok, extra) =>
    console.log((ok ? '  OK   ' : '  FAIL ') + label + (extra ? '  → ' + extra : ''));
  const waitText = (needle, timeout) => page.waitForFunction(
    (t) => document.body.innerText.includes(t), needle, { timeout: timeout || 120000 });

  await page.goto('http://localhost:8765/index.html', { waitUntil: 'networkidle' });
  await page.click('text=Ho capito, iniziamo');
  await page.waitForSelector('.tabbar');

  // Dati di esempio
  await page.click('.tabbar button:nth-child(5)');
  await page.click('text=Carica dati di esempio simulati');
  await waitText('estrazioni importate', 60000);

  async function openFromHome(tileTitle) {
    await page.click('.tabbar button:nth-child(1)');
    await page.waitForSelector('.tile');
    await page.click('.tile:has-text("' + tileTitle + '")');
  }

  // Ritardatari
  await openFromHome('Ritardatari');
  await waitText('Tutti i numeri');
  report('ritardatari', (await page.textContent('main')).includes('massimo storico'));

  // Hot / Cold
  await openFromHome('Numeri hot');
  await waitText('Trend: frequenza recente');
  await page.click('.chip:has-text("Overdue") >> nth=0');
  await waitText('Ritardo attuale elevato');
  report('hot/cold con filtri combinati', true);

  // Ambi
  await openFromHome('Ambi');
  await page.click('button:has-text("Genera ambi")');
  await waitText('AMBI STATISTICAMENTE INTERESSANTI');
  const pairText = await page.textContent('main');
  report('ambi generati', pairText.includes('Uscite') && pairText.includes('Rapporto'));
  await page.click('button:has-text("Perché?") >> nth=0');
  await waitText('Uscite congiunte:');
  report('spiegazione "Perché?"', true);

  // Terni
  await openFromHome('Terni');
  await page.click('button:has-text("Genera terni")');
  await waitText('TOP');
  report('terni generati', (await page.$$('main .ball')).length >= 30,
    (await page.$$('main .ball')).length + ' numeri');

  // Multi-ruota
  await openFromHome('Multi-ruota');
  await page.click('button:has-text("Analizza tutte le ruote")');
  await waitText('Numeri con segnali su più ruote', 180000);
  report('multi-ruota: numeri', true);
  await page.click('.segmented button:has-text("Ambi")');
  await waitText('TOP AMBI MULTI-RUOTA');
  await page.click('.segmented button:has-text("Cinquina")');
  await waitText('CINQUINA MULTI-RUOTA');
  report('multi-ruota: ambi e cinquina', true);

  // Monte Carlo
  await openFromHome('Monte Carlo');
  await page.click('button:has-text("Avvia simulazione")');
  await waitText('Conclusione', 180000);
  const mc = await page.textContent('main');
  report('monte carlo eseguito', mc.includes('Uniformità delle frequenze'));
  report('conclusione onesta sulla casualità',
    mc.includes('compatibili con un processo casuale') || mc.includes('scostamenti'));

  // Trova pattern
  await openFromHome('Trova pattern');
  await page.click('button:has-text("🔍 Trova pattern")');
  await waitText('Pattern esaminati', 180000);
  const pat = await page.textContent('main');
  report('pattern trovati', pat.includes('molteplicità dei test'));

  // AI Analyst
  await openFromHome('AI Analyst');
  await page.click('button:has-text("Esegui")');
  await waitText('Campioni train', 300000);
  const ml = await page.textContent('main');
  const auc = (ml.match(/AUC[\s\S]{0,40}?(0,\d{3})/) || [])[1];
  report('modello valutato', !!auc, 'AUC ' + auc);
  report('verdetto onesto', ml.includes('Nessun vantaggio predittivo dimostrato')
    || ml.includes('non va interpretato come capacità predittiva'));

  // Backtest
  await openFromHome('Backtest');
  await page.click('button:has-text("Esegui backtest")');
  await waitText('Risultati teorici', 300000);
  const bt = await page.textContent('main');
  report('backtest eseguito', bt.includes('ROI teorico') && bt.includes('Baseline'));
  report('protezione data leakage documentata', bt.includes('limite temporale stretto'));

  await page.screenshot({ path: 'screenshot-backtest.png' });
  await page.click('.tabbar button:nth-child(1)');
  await page.waitForSelector('.tile');
  await page.screenshot({ path: 'screenshot-home.png' });

  await browser.close();
  console.log('');
  if (errors.length) {
    console.log('ERRORI:');
    [...new Set(errors)].slice(0, 12).forEach((e) => console.log('  ' + e));
    process.exit(1);
  }
  console.log('Nessun errore JavaScript.');
})().catch((e) => { console.error('FALLITO:', e.message); process.exit(1); });
