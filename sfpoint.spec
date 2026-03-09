# -*- mode: python ; coding: utf-8 -*-
# sfpoint.spec — PyInstaller config for SFPoint.app

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

block_cipher = None

# --- PyObjC hidden imports ---
pyobjc_hidden = collect_submodules("objc") + collect_submodules("AppKit") + collect_submodules("Foundation") + collect_submodules("Cocoa") + collect_submodules("PyObjCTools")
pyobjc_datas = collect_data_files("objc") + collect_data_files("AppKit") + collect_data_files("Foundation")

# --- sounddevice is not used here, but pynput needs its darwin backend ---
pynput_hidden = [
    "pynput.keyboard._darwin",
    "pynput.mouse._darwin",
    "pynput._util.darwin",
]

a = Analysis(
    ["main.py"],
    pathex=["."],
    binaries=[],
    datas=[
        ("logo.png", "."),
        ("logo_small.png", "."),
    ] + pyobjc_datas,
    hiddenimports=[
        *pyobjc_hidden,
        *pynput_hidden,
        "PyQt6",
        "PyQt6.QtCore",
        "PyQt6.QtGui",
        "PyQt6.QtWidgets",
        "PyQt6.sip",
        "numpy",
        "plistlib",
        "ctypes",
        "ctypes.util",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "unittest", "test"],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="SFPoint",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    target_arch=None,
    codesign_identity=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    name="SFPoint",
)

app = BUNDLE(
    coll,
    name="SFPoint.app",
    icon="SFPoint.icns",
    bundle_identifier="so.saasfactory.sfpoint",
    info_plist={
        "LSUIElement": True,
        "CFBundleName": "SFPoint",
        "CFBundleDisplayName": "SFPoint",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1",
        "NSAccessibilityUsageDescription": "SFPoint needs Accessibility to detect global hotkeys and display screen annotations.",
        "NSAppleEventsUsageDescription": "SFPoint uses AppleScript for system integration.",
        "NSHighResolutionCapable": True,
    },
)
