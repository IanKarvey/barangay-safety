#!/usr/bin/env bash
# Build and deploy the web admin dashboard.
#
#   ./deploy_web.sh
#
# Use this rather than running the commands by hand: two of the steps between
# build and deploy are easy to forget and fail silently when missed.
#
# ── 1. The bundle is renamed per deploy ──────────────────────────────────────
#
# Flutter always emits `main.dart.js`. Browsers cache it by URL, so a browser
# that loaded any earlier build keeps running it until its cache entry expires,
# whatever has since been deployed. On 2026-10-14 that is exactly what
# happened: fixes were live on the server and verifiably in the served
# JavaScript, while the dashboard in the browser still behaved like the build
# before them.
#
# Renaming the file to `main.<build>.js` and pointing the bootstrap at it gives
# every deploy a URL no browser has seen, so there is nothing stale to reuse.
# (firebase.json then lets that unique file cache forever, and makes
# everything else revalidate.)
#
# ── 2. The service worker is replaced ────────────────────────────────────────
#
# `--pwa-strategy=none` stops Flutter generating a caching service worker, but
# it still writes an EMPTY `flutter_service_worker.js`. That does nothing for
# browsers that already registered the old caching worker, which keep serving
# their cached copy and never ask the server. `web/flutter_service_worker.js` is
# a worker that unregisters itself and clears its caches; copying it over the
# empty one is what removes the stale registrations already out there.
set -euo pipefail

cd "$(dirname "$0")"

BUILD_ID="$(date +%m%d-%H%M)"

if [ ! -f env.json ]; then
  echo "env.json not found — copy env.example.json to env.json and fill in your keys." >&2
  exit 1
fi

echo "── Building web dashboard (build $BUILD_ID) ───────────────────────────"
flutter build web -t lib/main_web.dart --pwa-strategy=none --no-wasm-dry-run \
  --dart-define-from-file=env.json --dart-define=BUILD_ID="$BUILD_ID"

echo
echo "── Fingerprinting the app bundle ───────────────────────────────────────"
mv build/web/main.dart.js "build/web/main.$BUILD_ID.js"
sed -i "s/main\.dart\.js/main.$BUILD_ID.js/g" build/web/flutter_bootstrap.js
if grep -q 'main\.dart\.js' build/web/flutter_bootstrap.js; then
  echo "   FAILED: bootstrap still references main.dart.js" >&2
  exit 1
fi
echo "   main.$BUILD_ID.js"

# version.json is what every open tab compares itself against
# (lib/screens/web/web_update_banner.dart). It must change on every deploy and
# must never be cached — firebase.json already serves *.json with no-cache.
printf '{"build":"%s"}\n' "$BUILD_ID" > build/web/version.json
echo "   version.json -> $BUILD_ID"

echo
echo "── Restoring the self-destructing service worker ───────────────────────"
cp web/flutter_service_worker.js build/web/flutter_service_worker.js
echo "   $(wc -c < build/web/flutter_service_worker.js) bytes (an empty file here means the copy failed)"

echo
echo "── Deploying to Firebase Hosting ───────────────────────────────────────"
firebase deploy --only hosting

echo
echo "Live: https://barangay-safety.web.app   (build $BUILD_ID)"
