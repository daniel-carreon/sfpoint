# -*- mode: python ; coding: utf-8 -*-
# sfpoint.spec — PyInstaller config for SFPoint.app (laser only)

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

block_cipher = None

# --- PyObjC hidden imports ---
pyobjc_hidden = (
    collect_submodules("objc")
    + collect_submodules("AppKit")
    + collect_submodules("Foundation")
    + collect_submodules("Cocoa")
    + collect_submodules("PyObjCTools")
)
pyobjc_datas = (
    collect_data_files("objc")
    + collect_data_files("AppKit")
    + collect_data_files("Foundation")
)

# pynput's darwin backends + Quartz (CGPreflightListenEventAccess lives there)
pynput_hidden = [
    "pynput.keyboard._darwin",
    "pynput.mouse._darwin",
    "pynput._util.darwin",
    "Quartz",
]

a = Analysis(
    ["main.py"],
    pathex=["."],
    binaries=[],
    datas=[("logo_small.png", ".")] + pyobjc_datas,
    hiddenimports=[
        *pyobjc_hidden,
        *pynput_hidden,
        "PyQt6",
        "PyQt6.QtCore",
        "PyQt6.QtGui",
        "PyQt6.QtWidgets",
        "PyQt6.sip",
        "plistlib",
        "ctypes",
        "ctypes.util",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "unittest", "test", "numpy", "PIL"],
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
        "CFBundleShortVersionString": "2.0.0",
        "CFBundleVersion": "2",
        "NSAccessibilityUsageDescription": "SFPoint necesita escuchar el atajo global Option+P para encender y apagar el laser.",
        "NSHighResolutionCapable": True,
    },
)
