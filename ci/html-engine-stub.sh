#!/bin/sh
# Writes the HTML engine's module as an empty placeholder and the build stamp that
# packages/html-engine/scripts/wasm.ts compares against, so `bun run build` skips Cargo.
# The hash mirrors sourcesHash(): each source's repository-relative name, a NUL byte,
# its bytes, and a NUL byte, concatenated in name order, then SHA-256.
#
# Use this only to ship the web editor without HTML import. To get a working engine,
# build it where Rust is installed: rm wasm/html-engine.wasm.sha256 && bun run build:wasm
#
#   sh ci/html-engine-stub.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
pkg="$root/packages/html-engine"
out="$pkg/wasm/html-engine.wasm"
stamp="$out.sha256"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

{
  printf '%s\n' "$root/Cargo.toml" "$root/Cargo.lock" "$root/rust-toolchain.toml" "$pkg/crate/Cargo.toml"
  find "$pkg/crate/src" -type f -name '*.rs'
} > "$work/files"

while IFS= read -r file; do
  printf '%s\t%s\n' "${file#"$root"/}" "$file"
done < "$work/files" | LC_ALL=C sort -k1,1 > "$work/names"

tab=$(printf '\t')
: > "$work/blob"
while IFS=$tab read -r name file; do
  printf '%s' "$name" >> "$work/blob"
  printf '\0' >> "$work/blob"
  cat "$file" >> "$work/blob"
  printf '\0' >> "$work/blob"
done < "$work/names"

if command -v sha256sum >/dev/null 2>&1; then
  hash=$(sha256sum "$work/blob" | cut -d' ' -f1)
else
  hash=$(shasum -a 256 "$work/blob" | cut -d' ' -f1)
fi

mkdir -p "$pkg/wasm"
: > "$out"
printf '%s\n' "$hash" > "$stamp"
echo "html-engine stub: $out"
echo "html-engine stamp: $hash"
