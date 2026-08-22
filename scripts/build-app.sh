#!/bin/bash
# build-app.sh — Compila SFPoint (Swift/SPM) y ensambla dist/SFPoint.app.
# Patron heredado de SFCast/SFlow v3, candados de firma incluidos.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== SFPoint build ==="

echo "[1/4] swift build -c release"
swift build -c release 2>&1 | tail -2

echo "[2/4] Ensamblando bundle"
APP="$ROOT/dist/SFPoint.app"
for i in 1 2 3; do
    rm -rf "$ROOT/dist" 2>/dev/null && break || sleep 1
done
if [ -e "$ROOT/dist" ]; then
    echo "ERROR: no se pudo limpiar dist/. Abortando."
    exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SFPoint "$APP/Contents/MacOS/SFPoint"
cp Info.plist "$APP/Contents/Info.plist"
[ -f logo_small.png ] && cp logo_small.png "$APP/Contents/Resources/logo_small.png"
[ -f assets/SFPoint.icns ] && cp assets/SFPoint.icns "$APP/Contents/Resources/SFPoint.icns"

echo "[3/4] Firmando"
# CANDADO: firma SIEMPRE con cert local ESTABLE, JAMAS ad-hoc — ad-hoc cambia el
# cdhash en cada rebuild y macOS revoca Monitorizacion de entrada, que es
# EXACTAMENTE el permiso del que depende ⌥P. Una app firmada ad-hoc se ve viva
# y queda sorda sin decir nada.
IDENTITY="SFlow Dev"
if ! security find-certificate -c "$IDENTITY" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
    echo "   Cert '$IDENTITY' no existe — crealo con software/sflow-next/scripts/make-cert.sh"
    exit 1
fi
# Timeout perl: con la SESION BLOQUEADA codesign se cuelga para siempre.
if ! perl -e 'alarm 120; exec @ARGV' codesign --force --deep --sign "$IDENTITY" "$APP"; then
    echo "ERROR: no se pudo firmar. Si tardo 120s: la Mac esta BLOQUEADA — desbloquea y reintenta."
    exit 1
fi
codesign --verify --strict "$APP" || { echo "ERROR: firma no verifica"; exit 1; }
echo "   Firmado con '$IDENTITY' (TCC estable entre rebuilds)"

echo "[4/4] Listo"
echo "  App:    $APP"
echo "  Tamano: $(du -sh "$APP" | cut -f1)"
