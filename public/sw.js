// Service worker mínimo. Existe por dois motivos: o Chrome só oferece
// "Instalar" para uma página que registra um, e ele é o ponto de partida do
// PWA que vem depois.
//
// Deliberadamente não guarda nada em cache. Este painel mostra e-mail, agenda
// e tarefas de agora — servir uma cópia velha seria pior do que mostrar erro
// de rede. Cache offline entra quando houver uma estratégia por rota que
// saiba o que pode envelhecer e o que não pode.

self.addEventListener('install', () => {
  // Assume o controle na primeira carga, em vez de esperar a próxima visita.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  // Um handler de fetch é parte do critério de instalação do Chrome. Este
  // repassa a requisição sem tocar nela.
  event.respondWith(fetch(event.request));
});

// Avisos dos agentes (Web Push). O servidor manda título, texto, a tarefa a
// abrir e uma tag: avisos com a mesma tag se substituem em vez de empilhar.
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { data = {}; }
  const title = typeof data.title === 'string' && data.title ? data.title : 'Daily';
  event.waitUntil(self.registration.showNotification(title, {
    body: typeof data.body === 'string' ? data.body : '',
    tag: typeof data.tag === 'string' ? data.tag : undefined,
    renotify: typeof data.tag === 'string',
    icon: '/icons/icon-192.png',
    data: { url: typeof data.url === 'string' ? data.url : '/' },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  // Só caminhos desta origem: o clique nunca leva para fora do painel.
  const target = new URL(event.notification.data?.url || '/', self.location.origin);
  if (target.origin !== self.location.origin) return;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (new URL(client.url).origin !== self.location.origin) continue;
      await client.focus();
      if ('navigate' in client) await client.navigate(target.href).catch(() => {});
      return;
    }
    await self.clients.openWindow(target.href);
  })());
});
