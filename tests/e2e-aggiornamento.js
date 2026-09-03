/* Aggiornamento automatico, quaterne e terzine per ambetto.

   Il caso che conta è il terzo: si svuota l'archivio del SuperEnalotto delle
   ultime venti estrazioni e si verifica che l'app se ne accorga da sola e le
   reimporti, senza che nessuno glielo chieda. */
const { chromium } = require('playwright-core');
(async () => {
  const browser = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push('PAGEERROR: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text()); });
  const report = (l, ok, extra) => console.log((ok ? '  OK   ' : '  FAIL ') + l + (extra ? '  → ' + extra : ''));

  await page.goto('http://localhost:8765/index.html', { waitUntil: 'networkidle' });
  await page.click('text=Ho capito, iniziamo');
  await page.waitForSelector('.tabbar', { timeout: 5000 });
  await page.click('.tabbar button:nth-child(5)');
  await page.waitForFunction(() => !document.body.innerText.includes('Lettura dell’indice in corso'), null, { timeout: 20000 });
  await page.click('button:has-text("Carica lo storico ufficiale") >> nth=0');
  await page.waitForFunction(() => document.body.innerText.includes('estrazioni aggiunte'), null, { timeout: 300000 });
  report('storico caricato', true);

  // aggiornamento automatico: interruttore e controllo manuale
  const dati = await page.textContent('main');
  report('interruttore aggiornamento', dati.includes('Aggiornamento automatico'));
  await page.click('button:has-text("Controlla adesso")');
  await page.waitForFunction(() => /Archivio già aggiornato|Nuova estrazione analizzata/.test(document.body.innerText), null, { timeout: 30000 });
  const esito = await page.textContent('main');
  report('controllo manuale risponde', /Archivio già aggiornato|Nuova estrazione/.test(esito),
    (esito.match(/Archivio già aggiornato[^.]*\./) || esito.match(/Nuova estrazione[^.]*\./) || [''])[0]);

  // simula un'estrazione arretrata: l'app deve accorgersene e reimportare
  const simulato = await page.evaluate(async () => {
    await Lotto.db.deleteGame('superenalotto');
    const text = await fetch('data/superenalotto-storico.csv').then(r => r.text());
    const righe = text.trim().split('\n');
    const parziale = righe.slice(0, righe.length - 20).join('\n');
    await Lotto.db.insertDraws(Lotto.archive.parseArchive(parziale, 'superenalotto'), 'test');
    await Lotto.app.syncDraws();
    const prima = Lotto.app.state.counts.superenalotto;
    const esito = await Lotto.app.checkForNewDraws();
    return { prima, dopo: Lotto.app.state.counts.superenalotto, aggiornati: esito ? esito.updated : null };
  });
  report('rileva e importa le estrazioni mancanti',
    simulato.dopo > simulato.prima, JSON.stringify(simulato));

  // quaterne
  await page.click('.tabbar button:nth-child(2)');
  await page.click('text=Quaterne');
  await page.click('button:has-text("Genera quaterne")');
  await page.waitForFunction(() => document.body.innerText.includes('TOP'), null, { timeout: 60000 });
  const quad = await page.textContent('main');
  report('quaterne generate', quad.includes('QUATERNE'));
  report('quattro numeri per riga', (await page.$$('.ball')).length >= 40, (await page.$$('.ball')).length + ' palline');

  // ambetto
  await page.click('.topbar .back');
  await page.click('text=Terzine per ambetto');
  await page.click('button:has-text("Genera terzine")');
  await page.waitForFunction(() => document.body.innerText.includes('TERZINE'), null, { timeout: 60000 });
  const amb = await page.textContent('main');
  report('terzine generate', amb.includes('TERZINE'));
  report('spiega l’ambetto', amb.includes('almeno due') && amb.includes('1 su 137'));
  report('mostra i tre ambi interni', (amb.match(/ambo \d/g) || []).length >= 3);
  report('avverte sulla selezione', amb.includes('terzine esaminate'));

  await browser.close();
  console.log('');
  if (errors.length) { console.log('ERRORI:'); [...new Set(errors)].slice(0,8).forEach(e=>console.log('  '+e)); process.exit(1); }
  console.log('Nessun errore JavaScript.');
})().catch((e) => { console.error('FALLITO:', e.message); process.exit(1); });
