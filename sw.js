// Service worker di Pari: rende l'app installabile e la apre anche senza rete.
// Pagine: prima la rete, così gli aggiornamenti arrivano subito; la copia in cache serve solo offline.
// Font, script e icone: dalla cache, aggiornati in background.
// Le chiamate a Supabase (altro dominio) non passano da qui.
// Quando cambia la lista dei file, aumenta VERSION.
const VERSION = "pari-v2";
const SHELL = [
  "./",
  "index.html",
  "privacy.html",
  "config.js",
  "manifest.webmanifest",
  "vendor/supabase.js",
  "fonts/fonts.css",
  "fonts/FamiljenGrotesk-latin.woff2",
  "fonts/FamiljenGrotesk-latin-ext.woff2",
  "fonts/Figtree-latin.woff2",
  "fonts/Figtree-latin-ext.woff2",
  "fonts/IBMPlexMono-400-latin.woff2",
  "fonts/IBMPlexMono-400-latin-ext.woff2",
  "fonts/IBMPlexMono-500-latin.woff2",
  "fonts/IBMPlexMono-500-latin-ext.woff2",
  "img/icon-192.png",
  "img/icon-512.png",
  "img/icon-maskable-192.png",
  "img/icon-maskable-512.png",
  "img/favicon-32.png",
  "img/apple-touch-icon.png"
];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET" || new URL(req.url).origin !== location.origin) return;

  if (req.mode === "navigate"){
    e.respondWith(fetch(req).then(res => {
      if (res.ok){ const copy = res.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
      return res;
    }).catch(() => caches.match(req, {ignoreSearch: true}).then(r => r || caches.match("index.html"))));
    return;
  }

  e.respondWith(caches.match(req).then(hit => {
    const net = fetch(req).then(res => {
      if (res.ok){ const copy = res.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
      return res;
    });
    if (hit){ e.waitUntil(net.catch(() => {})); return hit; }
    return net;
  }));
});
