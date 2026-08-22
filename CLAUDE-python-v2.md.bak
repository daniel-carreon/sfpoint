# CLAUDE.md — SFPoint

> For AI agents. SFPoint v2.0 is a **laser pointer and nothing else**.
> If you are about to add a tool, a toolbar or a settings panel: don't. They were
> all deleted on purpose (v1.0 had them, they went unused, and every one of them
> was surface that could break).

## What SFPoint is

A macOS menu bar app that draws a neon laser dot over everything.
`⌥P` cycles `off → ambar → morado → off`. `Esc` turns it off. That is the whole
product surface.

- Overlay is **always click-through** (`setIgnoresMouseEvents_(True)`), never
  steals focus (`NSWindowStyleMaskNonactivatingPanel`), one window per screen.
- Colors: ambar `#F59E0B`, morado `#8C27F1`. The click ripple is always the
  opposite color of the active laser.

## Commands

```bash
bash build.sh              # build into dist/
bash build.sh --install    # build + replace /Applications/SFPoint.app + launch
./venv/bin/python main.py  # dev mode
```

`build.sh` creates the venv on first run. Python 3.12+ (3.13 preferred).

## THE bug to never reintroduce: silent permission death

`⌥P` is a **listen-only CGEventTap** (pynput), gated by macOS behind
`kTCCServiceListenEvent` = *Privacy & Security > Input Monitoring*.

macOS binds that grant to the app's **code signature**. Ad-hoc signing
(`codesign --sign -`) has no stable identity, so the grant is pinned to the exact
cdhash. Any rebuild → new hash → the stored requirement stops matching → **the
tap is denied with zero errors** while System Settings still lists the app as
enabled. Symptom: the app opens, the icon is there, and no shortcut does
anything.

Ground truth is in the log, not in System Settings:

```bash
/usr/bin/log show --last 30m --predicate 'subsystem == "com.apple.TCC"' \
  --style compact | grep -i sfpoint
# Failed to match existing code requirement for subject
# so.saasfactory.sfpoint and service kTCCServiceListenEvent
```

Three defenses are in place. Keep all three:

1. **Stable signing identity** (`build.sh`): signs with `$SIGN_ID`
   (default `SFlow Dev`, a self-signed Code Signing cert in the login keychain).
   With a certificate the designated requirement is identifier + cert hash, so
   the grant survives rebuilds. The script warns loudly if it falls back to ad-hoc.
2. **Preflight + visible feedback** (`core/permissions.py`, `main.py`):
   `CGPreflightListenEventAccess` on launch, then `CGRequestListenEventAccess`.
   If still denied, the app SAYS SO (dialog + permanent menu item + the exact
   `tccutil reset` command). It must never fail quietly again.
3. **Fallback control surface** (`main.py` tray menu): the laser can be driven
   entirely from the menu bar. Cursor tracking uses `QCursor.pos()`, which needs
   no permission, so the laser still works when the hotkey is dead.

A watchdog (2s) re-checks the permission and restarts the pynput listener the
moment it is granted, so no relaunch is needed after approving.

Repair command when a record goes stale:

```bash
tccutil reset ListenEvent so.saasfactory.sfpoint
```

## Other invariants

- **`ditto`, never `cp -r`** when installing the bundle. `cp -r` corrupts bundle
  metadata and the app segfaults. `build.sh --install` does it right.
- **Balanced cursor hiding.** `CGDisplayHideCursor` increments a system-wide
  counter; it must be undone exactly. `ui/canvas.py` counts every hide and
  releases them all in `_restore_cursor()`, called on laser-off AND on quit.
  Leaking them leaves the user with no cursor at all, unrecoverably.
  (v1.0 called show 500 times and hoped. Don't go back to that.)
- **Qt threading.** pynput listeners run on their own threads. Every signal into
  Qt uses `Qt.ConnectionType.QueuedConnection`.
- **Efficiency contract.** Laser off = overlays hidden, no timers, no listeners.
  Laser on = one 60fps timer that repaints only the dirty rect (bounding box of
  dot + trail + ripples, unioned with the previous frame's). Never repaint a
  fullscreen overlay every frame.
- **Dock icon.** `LSUIElement` + `NSApplicationActivationPolicyAccessory`, set
  after the tray exists.
- **Bundle vs dev.** `config.py` reads `sys.frozen`; assets come from
  `sys._MEIPASS` in the bundle. There is no settings file anymore.

## Layout

```
main.py               tray icon + state machine + permission watchdog
config.py             colors, geometry, the one shortcut
core/hotkey.py        ⌥P (vk 35, or "π" on the macOS layout) + Esc
core/laser.py         renderer: bloom dot, 3-pass trail, ripple
core/permissions.py   Input Monitoring preflight / request / repair
ui/canvas.py          per-screen overlays, frame loop, cursor, dirty rects
build.sh              icon → venv → PyInstaller → sign → install
sfpoint.spec          PyInstaller config
```

Deleted in v2.0 (recover from git history if ever needed, but read the top of
this file first): `core/drawing.py`, `ui/toolbar.py`, `ui/settings.py`.

## Troubleshooting

| Problem | Cause / fix |
|---------|-------------|
| `⌥P` does nothing, app is running | Input Monitoring denied. Check the TCC log above, then `tccutil reset ListenEvent so.saasfactory.sfpoint` and restart |
| Worked before, broke after a rebuild | Ad-hoc signature. Rebuild with `SIGN_ID` set to a real identity |
| Cursor disappeared and won't come back | Unbalanced `CGDisplayHideCursor`. Quit SFPoint (it releases on quit); the bug is in `_restore_cursor()` |
| Laser lags or trails smear | Dirty-rect math in `_dirty_global()` is too tight; widen `LASER_PAD` / `RIPPLE_PAD` in `core/laser.py` |
| App segfaults after install | Installed with `cp -r`. Reinstall with `ditto` |
| App blocked by macOS | `xattr -cr /Applications/SFPoint.app` |
