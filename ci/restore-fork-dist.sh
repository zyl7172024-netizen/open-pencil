#!/bin/sh
# Puts the pinned CanvasKit and Taffy builds into packages/*/dist before `bun install`, so the
# workspace's postinstall (tools/release/fork-releases) finds hashes that match release.json and
# never reaches GitHub. Expects a directory laid out as:
#
#   <FORK_DIST_DIR>/canvaskit/dist/{canvaskit.js,canvaskit.wasm,index.d.ts,THIRD-PARTY-NOTICES.md}
#   <FORK_DIST_DIR>/taffy/dist/{taffy.js,taffy.wasm,taffy.d.ts,THIRD-PARTY-NOTICES.md}
#
# Keep that directory in a GitLab generic package or CI artifact, not in git: canvaskit.wasm is
# 9.3 MB. FORK_DIST_DIR defaults to <repository>/ci/artifacts/fork-dist.
#
#   FORK_DIST_DIR=/build/fork-dist sh ci/restore-fork-dist.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
src=${FORK_DIST_DIR:-"$root/ci/artifacts/fork-dist"}

for package in canvaskit taffy; do
  wasm="$src/$package/dist/$package.wasm"
  if [ ! -f "$wasm" ]; then
    echo "restore-fork-dist: missing $wasm" >&2
    echo "restore-fork-dist: set FORK_DIST_DIR to the directory holding those builds" >&2
    exit 1
  fi
  mkdir -p "$root/packages/$package/dist"
  cp -R -f "$src/$package/dist/." "$root/packages/$package/dist/"
  echo "restored packages/$package/dist"
done
