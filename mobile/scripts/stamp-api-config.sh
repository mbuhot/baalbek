#!/usr/bin/env bash
# Points a synced Capacitor bundle at a real API host.
#
# The packaged app cannot infer one: its WebView origin is the device, so
# `web`'s same-origin default (web/src/api.ts) would make it fetch its own
# bundle. `cap sync` copies web/dist — api-config.js included — into the native
# project, and this rewrites that one file in place, so the shared bundle needs
# no mobile-specific build.
#
#   stamp-api-config.sh <synced-public-dir> <api-base-url>
set -euo pipefail

public_dir="$1"
api_base_url="$2"

# The file ships from web/public/. Its absence means the bundle changed shape,
# which must fail here rather than in a hand-tested app.
if [ ! -f "$public_dir/api-config.js" ]; then
  echo "error: no api-config.js in $public_dir — web/public/api-config.js must ship in web/dist" >&2
  exit 1
fi

printf 'globalThis.__API_BASE_URL__ = "%s";\n' "$api_base_url" > "$public_dir/api-config.js"
echo "stamped $public_dir/api-config.js -> $api_base_url"
