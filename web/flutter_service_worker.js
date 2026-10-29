// A service worker whose only job is to remove itself.
//
// ## Why this file exists
//
// The web dashboard is built with `--pwa-strategy=none`, so Flutter no longer
// generates a caching service worker. That stops NEW visitors from ever
// getting a stale build — but it does nothing about browsers that already
// registered the old one, which keep serving the cached bundle from their own
// storage and never ask the server again. That is a trap: the fix is deployed,
// the server is serving it, and the person looking at the screen still sees
// the old app with no way to tell.
//
// It happened here on 2026-10-14: route and sign-out fixes were deployed and
// verified present in the live bundle, while the dashboard in the browser
// still behaved exactly like the build from before them.
//
// A browser re-fetches its registered service worker script on navigation and
// roughly every 24 hours. When it fetches this one, the script unregisters
// itself and deletes every cache it created, so the next load comes from the
// network. One reload later the browser is clean and this file is never asked
// for again.
//
// ## Do not "fix" this by adding caching back
//
// Offline support is worth very little to an admin dashboard — an official
// with no connection cannot read incidents or write a status change anyway,
// because both need Supabase. It costs a whole class of invisible staleness
// bugs. Keep this file until you are confident no browser still holds the old
// registration, and leave `--pwa-strategy=none` in the build command.

self.addEventListener('install', function (event) {
  // Take over immediately instead of waiting for existing tabs to close.
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    (async function () {
      // Drop every cache this origin holds — the old worker's precache is what
      // was actually serving the stale bundle.
      const names = await caches.keys();
      await Promise.all(names.map(function (name) {
        return caches.delete(name);
      }));

      await self.registration.unregister();

      // Reload any open tabs so they pick up the real files rather than
      // sitting on the version this worker was still serving a moment ago.
      const clients = await self.clients.matchAll({ type: 'window' });
      clients.forEach(function (client) {
        client.navigate(client.url);
      });
    })()
  );
});
