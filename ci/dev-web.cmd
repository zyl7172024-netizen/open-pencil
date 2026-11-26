@echo off
rem Web editor launcher for Windows. `bun run dev` needs Node to load this repository's TypeScript
rem configs, and the dev server spawns `bun` for its MCP automation, which a .cmd shim does not
rem satisfy. On Node 22.18+ (or 26.x, what CI uses) plain `bun run dev` works without this file.
set "PATH=%APPDATA%\npm\node_modules\bun\bin;%PATH%"
set "NODE_OPTIONS=--experimental-strip-types"
cd /d "%~dp0.."
node node_modules\vite\bin\vite.js
