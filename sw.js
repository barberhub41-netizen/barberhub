// ============================================================
// BarberHub — service worker
// Recebe o push quando o site está fechado e abre a página certa
// quando a pessoa toca na notificação.
// ============================================================

const CACHE = 'barberhub-v2';
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

// ------------------------------------------------------------
// Manifesto por barbearia
// O GitHub Pages só serve arquivo pronto, então é aqui que o
// manifesto de cada estabelecimento é montado, na hora do pedido.
// A página chama manifest.json?slug=...&nome=...&icone=...
// ------------------------------------------------------------
function manifestoDaBarbearia(url) {
  const nome = url.searchParams.get('nome') || 'BarberHub';
  const slug = url.searchParams.get('slug') || '';
  const icone = url.searchParams.get('icone');
  const base = url.pathname.replace(/manifest\.json$/, '');

  const icones = icone
    ? [
        { src: './icone-barbearia.png?u=' + encodeURIComponent(icone), sizes: '192x192', type: 'image/png', purpose: 'any' },
        { src: './icone-barbearia.png?u=' + encodeURIComponent(icone), sizes: '512x512', type: 'image/png', purpose: 'any' }
      ]
    : [
        { src: './icone-192.png', sizes: '192x192', type: 'image/png' },
        { src: './icone-512.png', sizes: '512x512', type: 'image/png' }
      ];

  return {
    name: nome,
    short_name: nome.length > 12 ? nome.slice(0, 12) : nome,
    description: 'Agende seu horário na ' + nome + '.',
    start_url: base + 'barbearia.html?slug=' + encodeURIComponent(slug),
    scope: base,
    display: 'standalone',
    orientation: 'portrait',
    background_color: '#141413',
    theme_color: '#d86b3f',
    lang: 'pt-BR',
    icons: icones
  };
}

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  if (url.origin !== location.origin) return;

  // manifesto montado na hora
  if (url.pathname.endsWith('manifest.json') && url.searchParams.has('slug')) {
    e.respondWith(new Response(
      JSON.stringify(manifestoDaBarbearia(url)),
      { headers: { 'Content-Type': 'application/manifest+json' } }
    ));
    return;
  }

  // ícone da barbearia: busca no armazenamento e devolve como se
  // fosse do próprio site, que é o que o manifesto exige
  if (url.pathname.endsWith('icone-barbearia.png')) {
    const externo = url.searchParams.get('u');
    if (externo) {
      e.respondWith(
        fetch(externo, { mode: 'cors' })
          .then((r) => r.ok ? r : fetch('./icone-512.png'))
          .catch(() => fetch('./icone-512.png'))
      );
      return;
    }
  }

  // o resto: cache só para arquivo estático, nunca para página
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
