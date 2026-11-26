# Offline pipeline handoff

This directory carries everything needed to build and deploy the **web editor** on an intranet
GitLab runner that cannot reach npm's registry (on a mirror) nor GitHub (not at all).

Scope: a static `dist/` served over an intranet IP. Desktop bundles, browser E2E, native tests,
Cloud images and release uploads are out of scope; see [Known limitations](#known-limitations).

## Facts verified on the internet-connected machine

| Item | Value |
|---|---|
| Bun | 1.4.4 (`packageManager`; 1.4.5 also reproduces the `unrun` failure below) |
| Node used for the build | 22.12 with `--experimental-strip-types`; CI uses 26.x where it is the default |
| Clean restore + install | `bun install --frozen-lockfile` after restoring the artifacts below |
| postinstall network | **none**: `packages/canvaskit: … is up to date`, `packages/taffy: … is up to date` |
| Lint | `bun run lint` → 0 warnings, 0 errors (two passes: 7440 files, then 4369 files) |
| Web build | `node node_modules/vite/bin/vite.js build` → `dist/` 35.8 MB, 308 files, `built in ~12s` |
| Dev server | `bun run dev` → HTTP 200, editor renders, MCP automation on port 7600 |

**`bun run build` cannot be used here.** Its `build:packages` step runs `bunx tsdown`, whose config
loader (`unrun`) cannot import this repository's `.ts` config under Bun 1.4.x:

```
[unrun] Import failed: Unknown file extension ".ts"
  for tools/release/package-artifacts/src/tsdown.ts
```

The same tsdown works when started with Node plus `--experimental-strip-types`, so the workspace
packages are built on the internet-connected side and shipped as artifacts. A pipeline must not
run `bun run build`, `bun run build:packages` or `bun run check`.

## Contents

| Path | What it is |
|---|---|
| `restore-fork-dist.sh` | Copies the pinned CanvasKit/Taffy builds into `packages/*/dist` **before** `bun install`, so postinstall's SHA-256 check matches and never reaches GitHub |
| `restore-package-dist.sh` | Copies the prebuilt `packages/*/dist` for the other 21 packages |
| `html-engine-stub.sh` | Writes an empty `packages/html-engine/wasm/html-engine.wasm` plus the build stamp that `scripts/wasm.ts` compares against, so `build:wasm` skips Cargo |
| `dev-web.cmd` | Windows launcher used when `bun run dev` cannot load TypeScript configs (Node < 22.18) |
| `gitlab-ci.yml` | Reference pipeline; copy to `.gitlab-ci.yml` or merge the jobs |
| `artifacts/` (not in git) | `fork-dist/` (9.6 MB) and `package-dist/` (about 37.5 MB) — the two artifact trees the scripts restore |
| `artifacts.tar.gz` | The same two trees compressed (11.9 MB), committed so a clone carries everything |

## Prerequisites on the intranet

1. **Runner image** with Node 22.12+ (26.x recommended, as upstream CI) and **Bun 1.4.4** on PATH.
   Verify with `command -v bun && bun --version`; a runner without Bun must fail loudly instead of
   silently skipping the step.
2. **npm mirror** that carries the whole lockfile, including platform binaries: `sharp`
   (`@img/sharp-<platform>`), `@tailwindcss/oxide`, `esbuild`, `oxlint`, `oxlint-tsgolint`.
3. **The two artifact trees**, shipped as `ci/artifacts.tar.gz` (11.9 MB, 47 MB unpacked); the pipeline unpacks them before restoring.
4. `NODE_OPTIONS=--experimental-strip-types` when Node is older than 22.18 (needed for tsdown
   only if packages are ever rebuilt; the lint step also needs it because `oxlint`'s JS plugins
   import `.ts`). Node 26 needs nothing extra.

## Where the 47 MB of build artifacts live

**This repository ships them as `ci/artifacts.tar.gz`**, unpacked by the pipeline's first step, so
a plain clone carries everything and no download is needed. The alternatives below remain for
repositories that prefer to keep binaries out of git.

### A. Commit the artifact trees into the repository

Remove the `ci/artifacts/` line from `.gitignore`, then `git add ci/artifacts && git commit`.

- **Pro**: the artifacts are versioned together with the commit that expects them; the pipeline
  needs no download step.
- **Con**: every clone and pull carries about 47 MB; every refresh of the artifacts adds another
  copy to git history, which cannot be reclaimed by deleting the files later.

### B. GitLab Generic Package (recommended)

The repository stays small and the artifacts are versioned by tag instead of commit.

One-time upload from a machine that has the trees:

```bash
tar -czf openpencil-ci-artifacts.tar.gz -C ci artifacts
curl --fail --header "PRIVATE-TOKEN: <personal-or-project-token>" \
  --upload-file openpencil-ci-artifacts.tar.gz \
  "https://<gitlab-host>/api/v4/projects/<project-id>/packages/generic/openpencil-ci-artifacts/0.17.0/openpencil-ci-artifacts.tar.gz"
```

Download in the job, before the restore scripts:

```yaml
  before_script:
    - curl --fail --header "JOB-TOKEN: $CI_JOB_TOKEN" --output ci-artifacts.tar.gz \
        "$CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/generic/openpencil-ci-artifacts/0.17.0/openpencil-ci-artifacts.tar.gz"
    - mkdir -p ci/artifacts
    - tar -xzf ci-artifacts.tar.gz -C ci/artifacts --strip-components=1
```

`--strip-components=1` drops the tarball's `artifacts/` prefix, leaving
`ci/artifacts/fork-dist` and `ci/artifacts/package-dist`, which is what the scripts expect by
default. Bump `0.17.0` whenever the artifacts are regenerated, and keep
`FORK_DIST_DIR`/`PACKAGE_DIST_DIR` unset.

### C. Any internal file server or artifact repository

Extract the tarball somewhere the job can read and point the job at it:

```yaml
  variables:
    FORK_DIST_DIR: /build/openpencil-artifacts/fork-dist
    PACKAGE_DIST_DIR: /build/openpencil-artifacts/package-dist
```

No code change is needed.

## Pipeline, in order

`ci/gitlab-ci.yml` already contains this. The order is not cosmetic:

| Step | Command | If skipped |
|---|---|---|
| 0 | `tar -xzf ci/artifacts.tar.gz -C ci/artifacts --strip-components=1` | the restore scripts find nothing; the job fails on step 1 |
| 1 | `sh ci/restore-fork-dist.sh` | `bun install` postinstall reaches GitHub and fails |
| 2 | `sh ci/restore-package-dist.sh` | `vite build` cannot resolve `@open-pencil/*`; lint reports `TS2307` for `@open-pencil/cli/commands` and `@open-pencil/fig` |
| 3 | `sh ci/html-engine-stub.sh` | only matters if something runs `build:wasm`; it keeps Cargo out of the picture |
| 4 | `bun install --frozen-lockfile` | nothing else can run |
| 5 | `bun run lint` | the quality gate is skipped; both oxlint passes must report 0 errors |
| 6 | `node node_modules/vite/bin/vite.js build` | no `dist/` |
| 7 | upload `dist/` as an artifact | nothing to deploy |

Notes:

- `bun install` runs the workspace `postinstall`. With the fork artifacts in place it prints
  `is up to date` and makes **no network calls**; without them it downloads from GitHub.
- `fork-release` (inside postinstall) checks that a `bun` executable is on PATH. Use the official
  Bun install (`~/.bun/bin`) or put the real `bun.exe`/`bun` directory on PATH; npm's `bun.cmd`
  shim is not enough on Windows.
- `bun install --frozen-lockfile` is safe: no dependency change is required for this pipeline.

## Custom build command for a pipeline UI

When the pipeline UI takes one command instead of a YAML job:

| Runner | Fill in |
|---|---|
| Linux / macOS | `sh ci/build-web.sh` |
| Windows | `powershell -ExecutionPolicy Bypass -File ci\build-web.ps1` |

Both run the same sequence: unpack `ci/artifacts.tar.gz`, restore the fork and package `dist`
trees, `bun install --frozen-lockfile`, `bun run lint`, then
`node node_modules/vite/bin/vite.js build`. They set `NODE_OPTIONS` themselves when Node is older
than 22.18. The deployable output is `dist/`.

Do not fill in `npm install`, `npm run build`, `bun run build` or `bun run check`: npm cannot
resolve `workspace:*`, and `build:packages` fails under Bun 1.4.x.

## Deployment

Publish the contents of `dist/` at the root of an intranet HTTP server. nginx example:

```nginx
server {
    listen 80;
    server_name _;
    root /var/www/openpencil;
    index index.html;
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

`dist/` is about 35.8 MB and contains `index.html`, `assets/`, `brand/`, `sw.js`,
`workbox-*.js` and `THIRD-PARTY-NOTICES.md`. The asset paths assume the app is served from `/`
(the repository's Vite `base` is the default `'/'`); serving it from a sub-path needs a `base`
change and a rebuild.

Behaviour by access mode:

| Access | Behaviour |
|---|---|
| `http://<intranet-ip>/` | Editor works. The PWA service worker is **not** registered because browsers require HTTPS or localhost; only offline caching is lost |
| HTTPS with a valid certificate | PWA install/offline caching also work |
| Without Cloud configured | Documents stay in local storage or open/save through the file picker |
| With `VITE_OPENPENCIL_FEEDBACK=on` at build time | The app tries to reach PostHog; on the intranet that times out. The provided pipeline does not set it, so telemetry stays off |

## Local development on the intranet

Verified on Windows with this repository's snapshot: `bun run dev` → HTTP 200, editor renders,
MCP automation on port 7600.

### Windows, step by step

```powershell
# In the repository root
powershell -ExecutionPolicy Bypass -File .\ci\local-run.ps1

# The real bun.exe directory, so the dev server can spawn `bun`
$env:PATH = "$env:APPDATA\npm\node_modules\bun\bin;$env:PATH"
# Only when Node is older than 22.18
$env:NODE_OPTIONS = "--experimental-strip-types"

bun install --frozen-lockfile
bun run dev
```

Two log lines are expected and harmless on an offline workstation:

| Log | Meaning |
|---|---|
| `Failed to fetch dynamically imported module: /src/boot.ts` on the first load | Vite is still optimizing dependencies; reload once |
| `Could not initialize provider 'fontsource' … TypeError: Failed to fetch` every 40 s | Web-font providers are unreachable offline; bundled fonts still work |

`ci/dev-web.cmd` sets PATH and NODE_OPTIONS and starts Vite, for a one-click launch.

Requirements:

1. `bun` **1.4.4** with the real executable on PATH (`~/.bun/bin`, or
   `%APPDATA%\npm\node_modules\bun\bin` for an npm install).
2. Node 22.18+ or 26.x (upstream CI uses 26.x). Older Node needs
   `NODE_OPTIONS=--experimental-strip-types`.
3. Port 1420 free (`strictPort`) and port 7600 free for the MCP automation server.
4. `bun install` needs the internal registry or a populated `~/.bun/install/cache`.

## Known limitations

| Not available | Reason |
|---|---|
| Import HTML / paste a web page | `html-engine.wasm` is a 0-byte placeholder; reinstalling Rust and running `bun run build:wasm` in `packages/html-engine` fixes it |
| `bun run build` / `bun run build:packages` / `bun run check` | tsdown's config loader fails under Bun 1.4.x; the pipeline rebuilds nothing and skips `check` |
| Browser E2E and visual regression | Playwright Chromium needs a download; the 294 visual baselines are `*-darwin.png` and fail on Linux |
| Native tests and desktop bundles | Rust toolchain and crates, WebView2, signing certificates, Updater private key |
| `check:audit` | Needs registry vulnerability data |
| Cloud images | Need Docker base images |
| npm publish / release uploads | Need internet and credentials |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `npm error EUNSUPPORTEDPROTOCOL: Unsupported URL Type "workspace:"` | `npm install` was used | Use `bun install` |
| `bun: command not found` / `command -v bun` empty | Runner without Bun | Add Bun 1.4.4 to the image, or fail the job early |
| `[unrun] Import failed` / `Unknown file extension ".ts"` | Something ran `build:packages` | Do not run `bun run build`; the packages arrive prebuilt |
| `html-engine.wasm is missing or older than its sources` | `ci/html-engine-stub.sh` not run | Run it before any build step |
| `canvaskit-…` download error or `fetch failed` | Fork artifacts not restored before install | Run `ci/restore-fork-dist.sh` first |
| `TS2307: Cannot find module '@open-pencil/fig'` or `@open-pencil/cli/commands` | `ci/restore-package-dist.sh` skipped or the artifact tree lacks `cli`/`oxlint-plugin` | Restore all 21 packages |
| `[MCP] Failed to spawn automation server: spawn bun ENOENT` (dev only) | `bun` resolves to a `.cmd` shim | Put the real `bun.exe` directory on PATH |
| Blank page, or asset 404s | Wrong nginx `root`/`alias`, or the app is served from a sub-path | Serve `dist/` at `/` |
| `Failed to resolve entry for package @open-pencil/...` | `packages/*/dist` missing | Restore the package artifacts |

## Acceptance checklist

- [ ] Runner: `bun --version` prints 1.4.4 and Node is 22.18+
- [ ] `sh ci/restore-fork-dist.sh` and `sh ci/restore-package-dist.sh` complete
- [ ] `bun install --frozen-lockfile` prints `is up to date` for canvaskit and taffy, no GitHub access
- [ ] `bun run lint` prints `0 warnings and 0 errors` for **both** oxlint passes
- [ ] `node node_modules/vite/bin/vite.js build` produces `dist/` (about 35.8 MB, 308 files)
- [ ] `http://<intranet-ip>/` loads the editor; create a document, draw a rectangle, save a `.fig`
- [ ] A workstation runs `bun run dev` and reaches `http://localhost:1420`

## Regenerating the artifacts (internet side)

Run where both npm and GitHub are reachable, then update the Generic Package version:

```bash
bun install
sh ci/restore-fork-dist.sh
sh ci/html-engine-stub.sh          # omit and build with Rust if HTML import is needed
for p in std scene-graph theme emit kiwi pen drawio mermaid fig dom-css design-jsx \
         html-engine core collab vue harness mcp feedback cloud cli oxlint-plugin; do
  ( cd "packages/$p" && NODE_OPTIONS=--experimental-strip-types \
      node ../../node_modules/tsdown/dist/run.mjs --config tsdown.config.ts ) || exit 1
done
# then copy each packages/<name>/dist into ci/artifacts/package-dist/packages/<name>/dist
```

`packages/cli` and `packages/oxlint-plugin` are part of the tree because
`packages/docs/.vitepress/theme/landing` imports `@open-pencil/cli/commands` and the lint step
loads the plugin; omitting them brings the 1-error lint result back.


