#!/bin/sh
# Restores the prebuilt workspace package output that `bun run build` would otherwise produce
# with tsdown. tsdown cannot load this repository's TypeScript config under Bun 1.4.x, so an
# offline pipeline skips `build:packages` and starts from artifacts built on a machine that has
# network access.
#
# Expects the same layout as the repository:
#
#   <PACKAGE_DIST_DIR>/packages/<name>/dist/...
#
# CanvasKit and Taffy are restored by ci/restore-fork-dist.sh instead, since their files come
# from the pinned fork releases rather than from a build.
#
# Keep the directory in a GitLab generic package or CI artifact: it is about 46 MB.
#
#   PACKAGE_DIST_DIR=/build/package-dist sh ci/restore-package-dist.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
src=${PACKAGE_DIST_DIR:-"$root/ci/artifacts/package-dist"}

if [ ! -d "$src/packages" ]; then
  echo "restore-package-dist: missing $src/packages" >&2
  echo "restore-package-dist: set PACKAGE_DIST_DIR to the directory holding the built packages" >&2
  exit 1
fi

count=0
for dir in "$src"/packages/*/dist; do
  [ -d "$dir" ] || continue
  package=$(basename "$(dirname "$dir")")
  case "$package" in
    canvaskit | taffy) continue ;;
  esac
  mkdir -p "$root/packages/$package/dist"
  cp -R -f "$dir/." "$root/packages/$package/dist/"
  count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
  echo "restore-package-dist: no package dist directories under $src/packages" >&2
  exit 1
fi

echo "restored dist for $count packages from $src"
