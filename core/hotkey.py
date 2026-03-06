"""Global hotkey listener for screen annotation.

Toggle-based: Ctrl+key toggles tools on/off.
Ctrl+A=arrow, Ctrl+R=rect, Ctrl+C=circle, Ctrl+F=freehand,
Ctrl+T=text, Ctrl+P=laser pointer, Ctrl+H=hide toolbar,
Ctrl+S=settings, Esc=deactivate.

Uses pynput with Qt signals (QueuedConnection required).
"""

from pynput import keyboard
from PyQt6.QtCore import QObject, pyqtSignal
from config import TOOL_SHORTCUTS, TOOL_LASER, SHORTCUT_HIDE_TOOLBAR, SHORTCUT_SETTINGS


class HotkeyListener(QObject):
    """Toggle-based Ctrl+key hotkey listener.

    Signals:
        tool_toggled(tool: str) — Ctrl+tool key pressed (toggle on/off)
        deactivated() — Esc pressed or tool toggled off
        hide_toolbar() — Ctrl+H pressed
        open_settings() — Ctrl+S pressed
        undo_requested() — Cmd+Z pressed
        clear_requested() — Cmd+Shift+Z pressed
    """

    tool_toggled = pyqtSignal(str)
    deactivated = pyqtSignal()
    laser_toggled = pyqtSignal(bool)  # independent laser on/off
    hide_toolbar = pyqtSignal()
    open_settings = pyqtSignal()
    undo_requested = pyqtSignal()
    clear_requested = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._ctrl_held = False
        self._cmd_held = False
        self._shift_held = False
        self._active_tool: str | None = None
        self._laser_on = False
        self._shortcuts = dict(TOOL_SHORTCUTS)
        self._listener: keyboard.Listener | None = None

    def start(self):
        self._listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release,
        )
        self._listener.daemon = True
        self._listener.start()

    def stop(self):
        if self._listener:
            self._listener.stop()
            self._listener = None

    def update_shortcuts(self, shortcuts: dict):
        self._shortcuts = dict(shortcuts)

    def _on_press(self, key):
        # Track modifiers
        if key in (keyboard.Key.ctrl_l, keyboard.Key.ctrl_r, keyboard.Key.ctrl):
            self._ctrl_held = True
        if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
            self._cmd_held = True
        if key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
            self._shift_held = True

        # Esc = deactivate
        if key == keyboard.Key.esc:
            if self._active_tool:
                self._active_tool = None
                self.deactivated.emit()
            return

        # Get char
        char = None
        try:
            char = key.char
        except AttributeError:
            pass

        if not char:
            return

        char_lower = char.lower()

        # Cmd+Z / Cmd+Shift+Z (undo/clear) — no Ctrl required
        if self._cmd_held and not self._ctrl_held:
            if char_lower == "z":
                if self._shift_held:
                    self.clear_requested.emit()
                else:
                    self.undo_requested.emit()
                return

        # Ctrl+key shortcuts (toggle-based)
        if not self._ctrl_held:
            return

        # Ctrl+H = hide/show toolbar
        if char_lower == SHORTCUT_HIDE_TOOLBAR:
            self.hide_toolbar.emit()
            return

        # Ctrl+S = settings
        if char_lower == SHORTCUT_SETTINGS:
            self.open_settings.emit()
            return

        # Tool shortcuts
        if char_lower in self._shortcuts:
            tool = self._shortcuts[char_lower]
            if tool == TOOL_LASER:
                # Laser is independent — toggle without affecting active tool
                self._laser_on = not self._laser_on
                self.laser_toggled.emit(self._laser_on)
            elif self._active_tool == tool:
                # Toggle off
                self._active_tool = None
                self.deactivated.emit()
            else:
                # Toggle on (deactivate previous if any)
                self._active_tool = tool
                self.tool_toggled.emit(tool)
            return

    def _on_release(self, key):
        if key in (keyboard.Key.ctrl_l, keyboard.Key.ctrl_r, keyboard.Key.ctrl):
            self._ctrl_held = False
        if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
            self._cmd_held = False
        if key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
            self._shift_held = False
