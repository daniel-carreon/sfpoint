#!/bin/bash
# install.sh — build + reemplaza /Applications/SFPoint.app + relanza.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build-app.sh"

echo "[5/7] Instalando"
pkill -x SFPoint 2>/dev/null || true
sleep 0.5
rm -rf /Applications/SFPoint.app
ditto "$ROOT/dist/SFPoint.app" /Applications/SFPoint.app
echo "  Instalado en /Applications/SFPoint.app"

# LaunchServices cachea el icono por ruta de bundle. Como arriba se hace
# rm -rf + ditto, el path desaparece un instante y el Dock cachea el icono
# generico; reinstalar con el icns correcto NO lo cambia por si solo.
# `touch` invalida la entrada, `lsregister` la vuelve a leer y, como SFPoint
# vive anclada al Dock, el Dock necesita reiniciarse para soltar su copia.
echo "[6/7] Refrescando el icono (LaunchServices + Dock)"
touch /Applications/SFPoint.app
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f /Applications/SFPoint.app || true
killall Dock 2>/dev/null || true

echo "[7/7] Lanzando"
open -n /Applications/SFPoint.app
sleep 2
if pgrep -x SFPoint >/dev/null; then
    echo "  SFPoint corriendo. ⌥P cicla: apagado → ambar → morado. Esc apaga."
else
    echo "  AVISO: no arranco. Revisa Consola.app filtrando por SFPoint."
fi
