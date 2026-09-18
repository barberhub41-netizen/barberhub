// ============================================================
// BarberHub — service worker
// Recebe o push quando o site está fechado e abre a página certa
// quando a pessoa toca na notificação.
// ============================================================

const CACHE = 'barberhub-v1';
const ESSENCIAIS = ['./', './index.html', './estilo.css', './manifest.json'];

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(ESSENCIAIS)).catch(() => {})
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((chaves) =>
      Promise.all(chaves.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Só serve do cache o que é do próprio site e não é do Supabase,
// para nunca devolver dado velho de agenda.
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  if (url.origin !== location.origin) return;
  if (url.pathname.endsWith('.html') || url.pathname === '/') return;

  e.respondWith(
    caches.match(e.request).then((achado) => achado || fetch(e.request))
  );
});

// ------------------------------------------------------------
// Push
// ------------------------------------------------------------
self.addEventListener('push', (e) => {
  let dados = { titulo: 'BarberHub', mensagem: '', link: 'index.html' };
  try {
    if (e.data) dados = { ...dados, ...e.data.json() };
  } catch (err) {
    if (e.data) dados.mensagem = e.data.text();
  }

  e.waitUntil(
    self.registration.showNotification(dados.titulo, {
      body: dados.mensagem,
      icon: './icone-192.png',
      badge: './icone-192.png',
      tag: dados.tipo || 'barberhub',
      data: { link: dados.link },
      vibrate: [80, 40, 80]
    })
  );
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const destino = new URL(e.notification.data?.link || 'index.html', self.location.origin + self.location.pathname.replace(/sw\.js$/, '')).href;

  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((abas) => {
      for (const aba of abas) {
        if (aba.url.startsWith(self.location.origin) && 'focus' in aba) {
          aba.navigate(destino);
          return aba.focus();
        }
      }
      return self.clients.openWindow(destino);
    })
  );
});
