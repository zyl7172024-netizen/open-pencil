# Prepares an unpacked copy of https://github.com/zyl7172024-netizen/open-pencil for local use.
# Run this from the repository root (the folder that contains ci\ and package.json):
#
#   powershell -ExecutionPolicy Bypass -File <path>\local-run.ps1
#   bun install --frozen-lockfile
#   bun run dev
#
# It unpacks ci\artifacts.tar.gz and puts the prebuilt dist trees where the app resolves them.
$ErrorActionPreference = 'Stop'

if (-not (Test-Path 'ci\artifacts.tar.gz')) {
  throw 'ci\artifacts.tar.gz not found. Run this from the repository root.'
}
if (-not (Test-Path 'package.json')) {
  throw 'package.json not found. Run this from the repository root.'
}

if (-not (Test-Path 'ci\artifacts\fork-dist')) {
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

$count = (Get-ChildItem 'ci\artifacts\package-dist\packages' -Directory | Measure-Object).Count
Write-Host "Restored CanvasKit, Taffy and $count package dist trees."
Write-Host 'Next:'
Write-Host '  bun install --frozen-lockfile'
Write-Host '  bun run dev'
