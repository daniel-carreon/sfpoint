"""Global hotkey — Option+P only.

Option+P cycles the laser: off → ambar → morado → off.
Esc turns it off.

Runs a pynput listener on its own thread; every signal crosses into Qt via
QueuedConnection (wired in main.py).
"""

from pynput import keyboard
from PyQt6.QtCore import QObject, pyqtSignal
from config import SHORTCUT_LASER, VK_P

# Option+P emits "π" on the macOS layout, so we match vk first, char second.
_OPTION_CHARS = {SHORTCUT_LASER, "π"}


class HotkeyListener(QObject):
    """Signals:
        cycle_requested() — Option+P
        off_requested()   — Esc
    """

    cycle_requested = pyqtSignal()
    off_requested = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._option_held = False
        self._blocked_held = False   # cmd/ctrl held → not our shortcut
        self._listener: keyboard.Listener | None = None

    # --- lifecycle ---

    def start(self):
        """Start (or restart) the listener. Safe to call repeatedly."""
        self.stop()
        self._option_held = False
        self._blocked_held = False
        self._listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release,
        )
        self._listener.daemon = True
        self._listener.start()

    def stop(self):
        if self._listener:
            try:
                self._listener.stop()
            except Exception:
                pass
            self._listener = None

    # --- callbacks (pynput thread) ---

    def _on_press(self, key):
        if key in (keyboard.Key.alt, keyboard.Key.alt_l, keyboard.Key.alt_r):
            self._option_held = True
            return
        if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r,
                   keyboard.Key.ctrl, keyboard.Key.ctrl_l, keyboard.Key.ctrl_r):
            self._blocked_held = True
            return

        if key == keyboard.Key.esc:
            self.off_requested.emit()
            return

        if not self._option_held or self._blocked_held:
            return

        if self._is_p(key):
            self.cycle_requested.emit()

    def _on_release(self, key):
        if key in (keyboard.Key.alt, keyboard.Key.alt_l, keyboard.Key.alt_r):
            self._option_held = False
        if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r,
                   keyboard.Key.ctrl, keyboard.Key.ctrl_l, keyboard.Key.ctrl_r):
            self._blocked_held = False

    # --- helpers ---

    @staticmethod
    def _is_p(key) -> bool:
        vk = getattr(key, "vk", None)
        if vk == VK_P:
            return True
        char = getattr(key, "char", None)
        return bool(char) and char.lower() in _OPTION_CHARS
