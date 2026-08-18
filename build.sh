#!/bin/bash
# build.sh — Build (and optionally install) SFPoint.app
#
#   bash build.sh              → build into dist/
#   bash build.sh --install    → build, then replace /Applications/SFPoint.app
#
# CRITICAL — SIGNING IDENTITY:
# Ad-hoc signing (`--sign -`) pins macOS permissions to the binary's cdhash, so
# EVERY rebuild silently kills Accessibility / Input Monitoring: the app looks
# alive and stops hearing hotkeys, with no error anywhere. Signing with a stable
# self-signed identity makes the permission survive rebuilds forever.
#
# Create the identity once (Keychain Access > Certificate Assistant >
# Create a Certificate: name it, type "Code Signing", self-signed), then:
#   SIGN_ID="Your Cert Name" bash build.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SIGN_ID="${SIGN_ID:-SFlow Dev}"
APP_DEST="/Applications/SFPoint.app"

echo "=== SFPoint Build ==="
echo ""

# --- Step 1: Icon ---
echo "[1/6] Icon..."
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

# --- Step 2: Venv ---
echo "[2/6] Venv + dependencies..."
if [ ! -d "venv" ]; then
    echo "   Creating venv..."
    python3.13 -m venv venv 2>/dev/null || python3.12 -m venv venv
    ./venv/bin/pip install --quiet --upgrade pip
    ./venv/bin/pip install --quiet -r requirements.txt
fi
./venv/bin/pip install --quiet pyinstaller
source venv/bin/activate

# --- Step 3: Clean ---
echo "[3/6] Cleaning previous builds..."
rm -rf build/ dist/

# --- Step 4: Build ---
echo "[4/6] Building .app (~1-2 min)..."
pyinstaller sfpoint.spec --noconfirm 2>&1 | tail -3

# --- Step 5: Sign ---
echo "[5/6] Signing..."
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --deep --sign "$SIGN_ID" dist/SFPoint.app
    echo "   Signed with stable identity: $SIGN_ID"
    echo "   Permissions will survive future rebuilds."
else
    codesign --force --deep --sign - dist/SFPoint.app
    echo "   !! WARNING: identity '$SIGN_ID' not found — signed AD-HOC."
    echo "   !! macOS permissions will break on the NEXT rebuild."
fi
codesign --verify --deep --strict dist/SFPoint.app && echo "   Signature verified."
echo "   Designated Requirement:"
codesign -d --requirements - dist/SFPoint.app 2>&1 | grep -v "^Executable=" | sed 's/^/     /'

# --- Step 6: Install ---
if [ "$1" == "--install" ]; then
    echo "[6/6] Installing to $APP_DEST..."
    killall SFPoint 2>/dev/null || true
    sleep 1
    # The old bundle goes to the Trash, never rm -rf: a bad build must stay undoable
    if [ -d "$APP_DEST" ]; then
        mv "$APP_DEST" "$HOME/.Trash/SFPoint-$(date +%Y%m%d-%H%M%S).app"
    fi
    ditto dist/SFPoint.app "$APP_DEST"   # ditto, NOT cp -r (cp corrupts the bundle)
    xattr -cr "$APP_DEST"
    echo "   Installed. Launching..."
    open "$APP_DEST"
else
    echo "[6/6] Skipping install (pass --install to replace $APP_DEST)."
fi

echo ""
echo "=== BUILD COMPLETE ==="
echo "  Bundle: $(pwd)/dist/SFPoint.app  ($(du -sh dist/SFPoint.app | cut -f1))"
echo ""
