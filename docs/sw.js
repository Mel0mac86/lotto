/* Service worker: mette in cache il guscio dell'app così funziona anche offline.
   I dati delle estrazioni stanno in IndexedDB e non passano da qui. */
'use strict';

const CACHE = 'lotto-ai-analyzer-v3';

const SHELL = [
  './',
  'index.html',
  'manifest.webmanifest',
  'data/manifest.json',
  'data/timesfm-previsioni.json',
  'css/app.css',
  'js/core/random.js',
  'js/core/models.js',
  'js/core/cooccurrence.js',
  'js/core/statistics.js',
  'js/core/scoring.js',
  'js/core/context.js',
  'js/core/combinations.js',
  'js/core/generators.js',
  'js/core/stats-tests.js',
  'js/core/montecarlo.js',
  'js/core/multiwheel.js',
  'js/core/backtest.js',
  'js/core/ml.js',
  'js/core/patterns.js',
  'js/core/validation.js',
  'js/core/explainer.js',
  'js/data/db.js',
  'js/data/import.js',
  'js/data/archive.js',
  'js/data/timesfm.js',
  'js/data/seed.js',
  'js/ui/dom.js',
  'js/ui/charts.js',
  'js/ui/views.js',
  'js/ui/views-analysis.js',
  'js/ui/views-generate.js',
  'js/ui/views-data.js',
  'js/ui/app.js',
  'js/worker.js',
  'icons/icon-180.png',
  'icons/icon-192.png',
  'icons/icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      // addAll fallisce in blocco se manca un file: si aggiunge uno a uno.
      .then((cache) => Promise.all(SHELL.map((url) => cache.add(url).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  // Le richieste verso le sorgenti dati dell'utente non vanno mai in cache.
  if (url.origin !== self.location.origin) return;
  // Nemmeno i CSV dello storico: si leggono una volta e finiscono in IndexedDB,
  // tenerne una seconda copia occuperebbe megabyte sul telefono per nulla.
  if (url.pathname.endsWith('.csv')) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      // Rete in background per aggiornare la copia locale.
      const network = fetch(request).then((response) => {
        if (response && response.status === 200) {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(request, copy));
        }
        return response;
      }).catch(() => cached);
      return cached || network;
    })
  );
});
