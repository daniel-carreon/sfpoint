#!/bin/bash
# install.sh — build + reemplaza /Applications/SFPoint.app + relanza.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build-app.sh"

echo "[5/6] Instalando"
pkill -x SFPoint 2>/dev/null || true
sleep 0.5
rm -rf /Applications/SFPoint.app
ditto "$ROOT/dist/SFPoint.app" /Applications/SFPoint.app
echo "  Instalado en /Applications/SFPoint.app"

echo "[6/6] Lanzando"
open -n /Applications/SFPoint.app
sleep 2
if pgrep -x SFPoint >/dev/null; then
    echo "  SFPoint corriendo. ⌥P cicla: apagado → ambar → morado. Esc apaga."
else
    echo "  AVISO: no arranco. Revisa Consola.app filtrando por SFPoint."
fi
