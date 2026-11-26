#!/bin/sh
# Builds the web editor offline: restores the shipped artifacts, installs dependencies, lints,
# and writes dist/. Use this as the pipeline's whole build step:
#
#   sh ci/build-web.sh
#
# Requires Bun 1.4.4 and Node 22.12+ (26.x recommended) on PATH. Run from anywhere.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

# Node older than 22.18 needs the flag for the TypeScript configs and oxlint's JS plugins.
node_version=$(node -p 'process.versions.node')
major=${node_version%%.*}
rest=${node_version#*.}
minor=${rest%%.*}
if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 18 ]; }; then
  export NODE_OPTIONS="${NODE_OPTIONS:-} --experimental-strip-types"
fi

if [ -f ci/artifacts.tar.gz ] && [ ! -d ci/artifacts/fork-dist ]; then
  mkdir -p ci/artifacts
  tar -xzf ci/artifacts.tar.gz -C ci/artifacts --strip-components=1
fi

# Before bun install: its postinstall then matches the local hashes and skips the download.
sh ci/restore-fork-dist.sh
sh ci/restore-package-dist.sh
sh ci/html-engine-stub.sh

bun install --frozen-lockfile
bun run lint
node node_modules/vite/bin/vite.js build

echo "Web build written to $root/dist"
