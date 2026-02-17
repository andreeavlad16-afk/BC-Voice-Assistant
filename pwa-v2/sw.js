const CACHE_NAME = 'bc-voice-v2-2213'; // bump version to force update
const ASSETS = ['/', '/styles.css', '/app.js']; // do not cache index.html

// Only cache static assets, not index.html
self.addEventListener('install', (e) => {
    e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(ASSETS)));
    self.skipWaiting();
});

self.addEventListener('activate', (e) => {
    e.waitUntil(
        caches.keys().then(keys =>
            Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
        )
    );
    self.clients.claim();
});

self.addEventListener('fetch', (e) => {
    const url = new URL(e.request.url);
    // Network-first for API calls
    if (url.pathname.startsWith('/api/')) return;
    // Network-first for index.html
    if (url.pathname === '/' || url.pathname.endsWith('index.html')) {
        e.respondWith(
            fetch(e.request)
                .then(response => {
                    // Optionally update cache
                    return response;
                })
                .catch(() => caches.match('/index.html'))
        );
        return;
    }
    // Cache-first for other assets
    e.respondWith(
        caches.match(e.request).then(cached => cached || fetch(e.request))
    );
});
