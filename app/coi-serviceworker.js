/* coi-serviceworker: enables crossOriginIsolated (SharedArrayBuffer) on static hosts
   by injecting COOP/COEP headers via a service worker. Based on the MIT-licensed
   coi-serviceworker pattern by Guido Zuidhof. */
if (typeof window === 'undefined') {
  // ---- service worker scope ----
  self.addEventListener('install', () => self.skipWaiting());
  self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
  self.addEventListener('message', (ev) => {
    if (ev.data && ev.data.type === 'deregister') {
      self.registration.unregister().then(() => self.clients.matchAll()).then((clients) => {
        clients.forEach((client) => client.navigate(client.url));
      });
    }
  });
  self.addEventListener('fetch', (event) => {
    const r = event.request;
    if (r.cache === 'only-if-cached' && r.mode !== 'same-origin') return;
    // cross-origin traffic (R2 video streams/uploads, APIs) must NOT be proxied:
    // Safari breaks media range requests through a SW, and long uploads die if
    // the worker is terminated mid-transfer. COEP credentialless handles these.
    try { if (new URL(r.url).origin !== self.location.origin) return; } catch (e) {}
    // navigations always revalidate so users never run a stale build
    const req = r.mode === 'navigate' ? new Request(r.url, { cache: 'no-cache' }) : r;
    event.respondWith(
      fetch(req).then((res) => {
        if (res.status === 0) return res;
        const h = new Headers(res.headers);
        h.set('Cross-Origin-Embedder-Policy', 'credentialless');
        h.set('Cross-Origin-Opener-Policy', 'same-origin');
        return new Response(res.body, { status: res.status, statusText: res.statusText, headers: h });
      }).catch((e) => console.error(e))
    );
  });
} else {
  // ---- page scope ----
  (() => {
    if (window.crossOriginIsolated) return;           // already isolated
    if (!window.isSecureContext) return;              // needs https
    const sw = navigator.serviceWorker;
    if (!sw) return;
    const src = document.currentScript && document.currentScript.src;
    if (!src) return;
    sw.register(src).then((reg) => {
      if (reg.active && !sw.controller) window.location.reload();
      reg.addEventListener('updatefound', () => window.location.reload());
    }).catch((e) => console.error('coi-sw registration failed', e));
  })();
}
