# Builds the web editor offline on Windows. Use as the pipeline's whole build step:
#
#   powershell -ExecutionPolicy Bypass -File ci\build-web.ps1
#
# Requires Bun 1.4.4 and Node 22.12+ (26.x recommended) on PATH. The HTML engine stub is not
# generated here: it is only needed when something runs build:wasm, which this script does not.
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
Write-Host "Repository root: $Root"

$nodeVersion = node -p "process.versions.node"
$parts = $nodeVersion.Split('.')
if ([int]$parts[0] -lt 22 -or ([int]$parts[0] -eq 22 -and [int]$parts[1] -lt 18)) {
  $env:NODE_OPTIONS = "$env:NODE_OPTIONS --experimental-strip-types".Trim()
}

if ((Test-Path 'ci\artifacts.tar.gz') -and -not (Test-Path 'ci\artifacts\fork-dist')) {
  New-Item -ItemType Directory -Force 'ci\artifacts' | Out-Null
  tar -xzf 'ci\artifacts.tar.gz' -C 'ci\artifacts' --strip-components=1
  if ($LASTEXITCODE -ne 0) { throw 'tar failed to unpack ci\artifacts.tar.gz' }
}

foreach ($package in 'canvaskit', 'taffy') {
  New-Item -ItemType Directory -Force "packages\$package\dist" | Out-Null
  Copy-Item "ci\artifacts\fork-dist\$package\dist\*" "packages\$package\dist\" -Recurse -Force
}

Get-ChildItem 'ci\artifacts\package-dist\packages' -Directory | ForEach-Object {
  $name = $_.Name
  New-Item -ItemType Directory -Force "packages\$name" | Out-Null
  Copy-Item (Join-Path $_.FullName 'dist') "packages\$name\dist" -Recurse -Force
}

bun install --frozen-lockfile
if ($LASTEXITCODE -ne 0) { throw 'bun install failed' }

bun run lint
if ($LASTEXITCODE -ne 0) { throw 'bun run lint failed' }

node node_modules\vite\bin\vite.js build
if ($LASTEXITCODE -ne 0) { throw 'vite build failed' }

Write-Host "Web build written to $Root\dist"
