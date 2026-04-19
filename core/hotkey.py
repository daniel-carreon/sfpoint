"""Global hotkey listener for screen annotation.

Toggle-based: Option+key toggles tools on/off.
Option+A=arrow, Option+R=rect, Option+C=circle, Option+F=freehand,
Option+T=text, Option+P=laser pointer, Option+H=hide toolbar,
Option+S=settings, Esc=deactivate.

Uses pynput with Qt signals (QueuedConnection required).
"""

from pynput import keyboard
from PyQt6.QtCore import QObject, pyqtSignal
from config import (
    TOOL_SHORTCUTS, TOOL_LASER, SHORTCUT_HIDE_TOOLBAR, SHORTCUT_SETTINGS,
    LASER_STATE_OFF, LASER_STATE_AMBAR, LASER_STATE_MORADO,
)


class HotkeyListener(QObject):
    """Toggle-based Option+key hotkey listener.

    Signals:
        tool_toggled(tool: str) — Option+tool key pressed (toggle on/off)
        deactivated() — Esc pressed or tool toggled off
        hide_toolbar() — Option+H pressed
        open_settings() — Option+S pressed
        undo_requested() — Cmd+Z pressed
        clear_requested() — Cmd+Shift+Z pressed
    """

    tool_toggled = pyqtSignal(str)
    deactivated = pyqtSignal()
    laser_toggled = pyqtSignal(int)  # laser state: 0=off, 1=ambar, 2=morado
    hide_toolbar = pyqtSignal()
    open_settings = pyqtSignal()
    undo_requested = pyqtSignal()
    clear_requested = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._option_held = False
        self._cmd_held = False
        self._shift_held = False
        self._active_tool: str | None = None
        self._laser_state = LASER_STATE_OFF  # cycles: off → ambar → morado → off
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
        if key in (keyboard.Key.alt_l, keyboard.Key.alt_r, keyboard.Key.alt):
            self._option_held = True
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

        # Get char — Option on macOS produces special chars, so also check vk
        char = None
        try:
            char = key.char
        except AttributeError:
            pass

        # On macOS, Option+key produces unicode chars (å, ®, ©, etc.)
        # Use vk (virtual key code) to get the original letter
        if self._option_held and hasattr(key, 'vk') and key.vk is not None:
            vk = key.vk
            # macOS virtual key codes for letters
            vk_map = {
                0: 'a', 11: 'b', 8: 'c', 2: 'd', 14: 'e', 3: 'f',
                5: 'g', 4: 'h', 34: 'i', 38: 'j', 40: 'k', 37: 'l',
                46: 'm', 45: 'n', 31: 'o', 35: 'p', 12: 'q', 15: 'r',
                1: 's', 17: 't', 32: 'u', 9: 'v', 13: 'w', 7: 'x',
                16: 'y', 6: 'z',
            }
            if vk in vk_map:
                char = vk_map[vk]

        if not char:
            return

        char_lower = char.lower()

        # Cmd+Z / Cmd+Shift+Z (undo/clear) — no Option required
        if self._cmd_held and not self._option_held:
            if char_lower == "z":
                if self._shift_held:
                    self.clear_requested.emit()
                else:
                    self.undo_requested.emit()
                return

        # Option+key shortcuts (toggle-based)
        if not self._option_held:
            return

        # Option+H = hide/show toolbar
        if char_lower == SHORTCUT_HIDE_TOOLBAR:
            self.hide_toolbar.emit()
            return

        # Option+S = settings
        if char_lower == SHORTCUT_SETTINGS:
            self.open_settings.emit()
            return

        # Tool shortcuts
        if char_lower in self._shortcuts:
            tool = self._shortcuts[char_lower]
            if tool == TOOL_LASER:
                # Cycle: off(0) → ambar(1) → morado(2) → off(0)
                self._laser_state = (self._laser_state % 3) + 1
                if self._laser_state > LASER_STATE_MORADO:
                    self._laser_state = LASER_STATE_OFF
                self.laser_toggled.emit(self._laser_state)
            elif self._active_tool == tool:
                self._active_tool = None
                self.deactivated.emit()
            else:
                self._active_tool = tool
                self.tool_toggled.emit(tool)
            return

    def _on_release(self, key):
        if key in (keyboard.Key.alt_l, keyboard.Key.alt_r, keyboard.Key.alt):
            self._option_held = False
        if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
            self._cmd_held = False
        if key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
            self._shift_held = False
