#!/bin/bash
# build.sh — Build SFPoint.app from source (one shot)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== SFPoint Build ==="
echo ""

# --- Step 1: Generate .icns if missing ---
echo "[1/5] Icon..."
if [ ! -f "SFPoint.icns" ]; then
    ICONSET="SFPoint.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        sips -z $size $size logo.png --out "$ICONSET/icon_${size}x${size}.png" > /dev/null 2>&1
        double=$((size * 2))
        sips -z $double $double logo.png --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o SFPoint.icns
    rm -rf "$ICONSET"
    echo "   SFPoint.icns created."
else
    echo "   SFPoint.icns already exists."
fi

# --- Step 2: Activate venv ---
echo "[2/5] Venv + PyInstaller..."
source venv/bin/activate
pip install pyinstaller --quiet 2>/dev/null

# --- Step 3: Clean ---
echo "[3/5] Cleaning previous builds..."
rm -rf build/ dist/

# --- Step 4: Build ---
echo "[4/5] Building .app (this takes ~1-2 min)..."
pyinstaller sfpoint.spec --noconfirm 2>&1 | tail -5

# --- Step 5: Sign ---
echo "[5/5] Signing..."
codesign --force --deep --sign - dist/SFPoint.app 2>/dev/null
codesign --verify --deep --strict dist/SFPoint.app 2>/dev/null && echo "   Signature OK." || echo "   Signature: warning (may still work)."

echo ""
echo "=== BUILD COMPLETE ==="
echo ""
echo "  File:    $(pwd)/dist/SFPoint.app"
echo "  Size:    $(du -sh dist/SFPoint.app | cut -f1)"
echo ""
echo "  To install:"
echo "    ditto dist/SFPoint.app /Applications/SFPoint.app"
echo ""
echo "  IMPORTANT: Use 'ditto' (not 'cp -r') to preserve bundle metadata."
echo ""

# Open dist folder
open dist/
