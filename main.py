"""SFPoint — Screen Annotation Tool.

Ctrl+key toggles annotation tools on/off.
Ctrl+A=arrow, Ctrl+R=rect, Ctrl+C=circle, Ctrl+F=freehand,
Ctrl+T=text, Ctrl+P=pointer, Ctrl+H=hide toolbar, Ctrl+S=settings.
Esc=deactivate, Cmd+Z=undo, Cmd+Shift+Z=clear all.
"""

import os
import plistlib
import signal
import sys
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QPixmap
from PyQt6.QtCore import Qt
from config import IS_BUNDLE, LOGO_PATH, LASER_STATE_OFF, LASER_STATE_AMBAR, LASER_STATE_MORADO, LASER_COLORS, load_prefs, save_prefs, COLOR_PALETTE
from core.hotkey import HotkeyListener
from ui.canvas import CanvasManager
from ui.toolbar import ToolbarWidget
from ui.settings import SettingsPanel


def _ensure_accessibility() -> bool:
    """Check Accessibility trust, prompting once on first launch."""
    import os as _os, json as _json
    settings_path = _os.path.expanduser("~/Library/Application Support/SFPoint/settings.json")

    try:
        from ApplicationServices import AXIsProcessTrustedWithOptions
        # Always call with prompt=False to activate the session — required for
        # pynput to receive events even when permission is already granted.
        trusted = AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": False})
        if trusted:
            return True
    except Exception:
        return True

    # Not trusted yet — prompt once, then stop asking.
    data = {}
    if _os.path.exists(settings_path):
        try:
            with open(settings_path) as f:
                data = _json.load(f)
        except Exception:
            pass

    if not data.get("accessibility_prompted"):
        try:
            from ApplicationServices import AXIsProcessTrustedWithOptions
            AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": True})
        except Exception:
            pass
        data["accessibility_prompted"] = True
        try:
            _os.makedirs(_os.path.dirname(settings_path), exist_ok=True)
            with open(settings_path, "w") as f:
                _json.dump(data, f, indent=2)
        except Exception:
            pass
    return False


def _ensure_input_monitoring() -> bool:
    """Check Input Monitoring, prompting once on first launch."""
    import os as _os, json as _json
    settings_path = _os.path.expanduser("~/Library/Application Support/SFPoint/settings.json")

    try:
        from Quartz import (
            CGEventTapCreate, kCGSessionEventTap, kCGHeadInsertEventTap,
            kCGEventTapOptionListenOnly, CGEventMaskBit, kCGEventKeyDown,
        )
        # Always attempt the tap — activates the Input Monitoring session for
        # this process, which pynput's internal CGEventTap depends on.
        tap = CGEventTapCreate(
            kCGSessionEventTap, kCGHeadInsertEventTap,
            kCGEventTapOptionListenOnly, CGEventMaskBit(kCGEventKeyDown),
            lambda proxy, type_, event, refcon: event, None,
        )
        if tap is not None:
            return True
    except Exception:
        return True

    # Tap failed — permission not granted. Alert once, then stop asking.
    data = {}
    if _os.path.exists(settings_path):
        try:
            with open(settings_path) as f:
                data = _json.load(f)
        except Exception:
            pass

    if data.get("input_monitoring_prompted"):
        return False

    import AppKit, subprocess
    alert = AppKit.NSAlert.alloc().init()
    alert.setMessageText_("Input Monitoring Required")
    alert.setInformativeText_(
        "SFPoint needs Input Monitoring to detect keyboard shortcuts.\n\n"
        "To enable it:\n"
        "1. Click \"Open System Settings\" below\n"
        "2. Click the \"+\" button\n"
        "3. Navigate to /Applications and select SFPoint\n"
        "4. Enable the toggle next to SFPoint\n"
        "5. Relaunch SFPoint"
    )
    alert.addButtonWithTitle_("Open System Settings")
    alert.addButtonWithTitle_("Done")
    response = alert.runModal()
    if response == AppKit.NSAlertFirstButtonReturn:
        subprocess.run([
            "open",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ])

    data["input_monitoring_prompted"] = True
    try:
        _os.makedirs(_os.path.dirname(settings_path), exist_ok=True)
        with open(settings_path, "w") as f:
            _json.dump(data, f, indent=2)
    except Exception:
        pass
    return False


# --- Launch Agent ---
_BUNDLE_ID = "so.saasfactory.sfpoint"
_LAUNCH_AGENT_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{_BUNDLE_ID}.plist")


def _is_launch_at_login() -> bool:
    return os.path.exists(_LAUNCH_AGENT_PATH)


def _set_launch_at_login(enabled: bool):
    if enabled:
        app_path = "/Applications/SFPoint.app" if IS_BUNDLE else ""
        if not app_path or not os.path.exists(app_path):
            return
        plist = {
            "Label": _BUNDLE_ID,
            "ProgramArguments": ["open", "-a", app_path],
            "RunAtLoad": True,
        }
        os.makedirs(os.path.dirname(_LAUNCH_AGENT_PATH), exist_ok=True)
        with open(_LAUNCH_AGENT_PATH, "wb") as f:
            plistlib.dump(plist, f)
    else:
        if os.path.exists(_LAUNCH_AGENT_PATH):
            os.remove(_LAUNCH_AGENT_PATH)


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    canvas = CanvasManager()
    toolbar = ToolbarWidget()
    settings = SettingsPanel()
    hotkey = HotkeyListener()

    # --- Restore persisted prefs ---
    prefs = load_prefs()
    if prefs["custom_color"]:
        from PyQt6.QtGui import QColor as _QColor
        COLOR_PALETTE[5] = _QColor(prefs["custom_color"])
    canvas.set_color_index(prefs["color_index"])
    canvas.set_stroke_width(prefs["stroke_width"])
    canvas.set_arrow_tip_first(prefs["arrow_tip_first"])
    toolbar.update_color(prefs["color_index"])
    toolbar.update_stroke(prefs["stroke_width"])
    toolbar.set_arrow_tip_first(prefs["arrow_tip_first"])

    # --- System Tray (menu bar icon) ---
    tray = QSystemTrayIcon()
    tray_icon = QIcon(QPixmap(LOGO_PATH))
    tray.setIcon(tray_icon)

    tray_menu = QMenu()
    settings_action = tray_menu.addAction("Settings")
    settings_action.triggered.connect(settings.toggle)

    tray_menu.addSeparator()

    login_action = tray_menu.addAction("Start with macOS")
    login_action.setCheckable(True)
    login_action.setChecked(_is_launch_at_login())
    login_action.triggered.connect(lambda checked: _set_launch_at_login(checked))

    tray_menu.addSeparator()

    quit_action = tray_menu.addAction("Quit SFPoint")
    quit_action.triggered.connect(app.quit)

    tray.setContextMenu(tray_menu)
    tray.show()

    # --- Connect signals (all QueuedConnection for thread safety) ---

    hotkey.tool_toggled.connect(
        lambda tool: _on_tool_toggled(canvas, toolbar, tool),
        Qt.ConnectionType.QueuedConnection,
    )
    hotkey.deactivated.connect(
        lambda: _on_deactivated(canvas, toolbar),
        Qt.ConnectionType.QueuedConnection,
    )
    hotkey.laser_toggled.connect(
        lambda state: _on_laser_toggled(canvas, toolbar, state),
        Qt.ConnectionType.QueuedConnection,
    )
    hotkey.hide_toolbar.connect(
        toolbar.toggle_visibility,
        Qt.ConnectionType.QueuedConnection,
    )
    hotkey.open_settings.connect(
        settings.toggle,
        Qt.ConnectionType.QueuedConnection,
    )
    hotkey.undo_requested.connect(
        canvas.undo,
        Qt.ConnectionType.QueuedConnection,
    )
    hotkey.clear_requested.connect(
        canvas.clear_all,
        Qt.ConnectionType.QueuedConnection,
    )

    # Settings can update hotkey shortcuts
    settings.shortcuts_changed.connect(
        hotkey.update_shortcuts,
        Qt.ConnectionType.QueuedConnection,
    )

    # --- Context menu signals from toolbar ---
    toolbar.tool_selected.connect(
        lambda tool: _on_context_tool(canvas, toolbar, hotkey, tool),
    )
    toolbar.color_selected.connect(
        lambda idx: _on_context_color(canvas, toolbar, idx),
    )
    toolbar.stroke_selected.connect(
        lambda w: _on_context_stroke(canvas, toolbar, w),
    )
    toolbar.undo_requested.connect(canvas.undo)
    toolbar.clear_requested.connect(canvas.clear_all)
    toolbar.settings_requested.connect(settings.toggle)
    toolbar.quit_requested.connect(app.quit)
    toolbar.deactivate_requested.connect(
        lambda: _on_deactivated(canvas, toolbar, hotkey),
    )
    toolbar.arrow_mode_toggled.connect(
        lambda tip_first: _on_arrow_mode(canvas, toolbar, tip_first),
    )

    # Right-click anywhere on canvas opens toolbar's context menu
    canvas.context_menu_requested.connect(
        lambda pos: toolbar._show_context_menu(pos),
    )

    # Show UI
    canvas.show()
    toolbar.show()

    # Request permissions (shows macOS prompts if not granted)
    _ensure_accessibility()
    _ensure_input_monitoring()

    hotkey.start()

    # --- Hide from Dock (menu bar only) ---
    # MUST be set AFTER all windows are shown
    try:
        import AppKit
        AppKit.NSApp.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)
    except Exception:
        pass

    print("SFPoint running.")
    print("  ^A=arrow  ^R=rect  ^C=circle  ^F=freehand")
    print("  ^T=text   ^P=pointer")
    print("  ^H=hide toolbar  ^S=settings")
    print("  \u2318Z=undo  \u2318\u21e7Z=clear  Esc=deactivate  Right-click=menu")

    exit_code = app.exec()
    hotkey.stop()
    sys.exit(exit_code)


def _on_tool_toggled(canvas: CanvasManager, toolbar: ToolbarWidget, tool: str):
    canvas.set_tool(tool)
    canvas.set_active(True)
    toolbar.update_tool(tool)
    toolbar.set_active(True)


def _on_deactivated(canvas: CanvasManager, toolbar: ToolbarWidget, hotkey=None):
    canvas.set_active(False)
    toolbar.set_active(False)
    if hotkey is not None:
        hotkey._active_tool = None


def _on_laser_toggled(canvas: CanvasManager, toolbar: ToolbarWidget, state: int):
    if state == LASER_STATE_OFF:
        canvas.set_laser(False)
        if not canvas.is_active:
            toolbar.set_active(False)
    else:
        color = LASER_COLORS[state]
        canvas.set_laser_color(color)
        canvas.set_laser(True)
        label = "laser" if state == LASER_STATE_AMBAR else "laser-morado"
        toolbar.update_tool(label)
        toolbar.set_active(True)


def _on_context_tool(canvas: CanvasManager, toolbar: ToolbarWidget, hotkey, tool: str):
    from config import TOOL_LASER
    if tool == TOOL_LASER:
        # Cycle laser state via context menu: off → ambar → morado → off
        hotkey._laser_state = (hotkey._laser_state % 3) + 1
        if hotkey._laser_state > LASER_STATE_MORADO:
            hotkey._laser_state = LASER_STATE_OFF
        if hotkey._laser_state == LASER_STATE_OFF:
            canvas.set_laser(False)
            if not canvas.is_active:
                toolbar.set_active(False)
        else:
            color = LASER_COLORS[hotkey._laser_state]
            canvas.set_laser_color(color)
            canvas.set_laser(True)
            label = "laser" if hotkey._laser_state == LASER_STATE_AMBAR else "laser-morado"
            toolbar.update_tool(label)
            toolbar.set_active(True)
    else:
        # If clicking the already-active tool, deactivate
        if canvas.is_active and canvas.current_tool == tool:
            canvas.set_active(False)
            toolbar.set_active(False)
            hotkey._active_tool = None
        else:
            canvas.set_tool(tool)
            canvas.set_active(True)
            toolbar.update_tool(tool)
            toolbar.set_active(True)
            hotkey._active_tool = tool


def _save_prefs(canvas: CanvasManager):
    custom_hex = COLOR_PALETTE[5].name() if len(COLOR_PALETTE) > 5 else None
    save_prefs(
        color_index=canvas.current_color_index,
        stroke_width=canvas._stroke_width,
        arrow_tip_first=canvas._arrow_tip_first,
        custom_color_hex=custom_hex,
    )


def _on_arrow_mode(canvas: CanvasManager, toolbar: ToolbarWidget, tip_first: bool):
    canvas.set_arrow_tip_first(tip_first)
    toolbar.set_arrow_tip_first(tip_first)
    _save_prefs(canvas)


def _on_context_color(canvas: CanvasManager, toolbar: ToolbarWidget, idx: int):
    canvas.set_color_index(idx)
    toolbar.update_color(idx)
    _save_prefs(canvas)


def _on_context_stroke(canvas: CanvasManager, toolbar: ToolbarWidget, width: float):
    canvas.set_stroke_width(width)
    toolbar.update_stroke(width)
    _save_prefs(canvas)


if __name__ == "__main__":
    main()
