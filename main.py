"""SFPoint — laser pointer for macOS.

Option+P cycles: off → ambar → morado → off.  Esc turns it off.
That is the whole app. It lives in the menu bar, has no Dock icon, and never
steals focus.

The menu bar icon mirrors the state AND doubles as the fallback control surface,
so the app is still fully usable if macOS ever revokes the hotkey permission.
"""

import os
import plistlib
import signal
import subprocess
import sys

from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu, QMessageBox
from PyQt6.QtGui import QIcon, QPixmap, QPainter, QColor, QRadialGradient, QActionGroup
from PyQt6.QtCore import Qt, QTimer, QPointF

from config import (
    IS_BUNDLE, LOGO_PATH, BUNDLE_ID, APP_PATH,
    LASER_OFF, LASER_AMBAR, LASER_MORADO, LASER_COLORS, LASER_LABELS,
)
from core.hotkey import HotkeyListener
from core.permissions import (
    has_input_monitoring, request_input_monitoring,
    open_settings_pane, repair_command,
)
from ui.canvas import LaserCanvas

_LAUNCH_AGENT_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{BUNDLE_ID}.plist")


# ── Launch at login ──────────────────────────────────────────────────

def _is_launch_at_login() -> bool:
    return os.path.exists(_LAUNCH_AGENT_PATH)


def _set_launch_at_login(enabled: bool):
    if enabled:
        if not IS_BUNDLE or not os.path.exists(APP_PATH):
            return
        plist = {
            "Label": BUNDLE_ID,
            "ProgramArguments": ["open", "-a", APP_PATH],
            "RunAtLoad": True,
        }
        os.makedirs(os.path.dirname(_LAUNCH_AGENT_PATH), exist_ok=True)
        with open(_LAUNCH_AGENT_PATH, "wb") as f:
            plistlib.dump(plist, f)
    elif os.path.exists(_LAUNCH_AGENT_PATH):
        os.remove(_LAUNCH_AGENT_PATH)


def _restart_app():
    """Relaunch from scratch — the only way to pick up a freshly granted TCC."""
    if IS_BUNDLE and os.path.exists(APP_PATH):
        subprocess.Popen(["/bin/sh", "-c", f"sleep 1; open -n '{APP_PATH}'"])
        QApplication.instance().quit()
    else:
        os.execv(sys.executable, [sys.executable] + sys.argv)


# ── Menu bar icon ────────────────────────────────────────────────────

def _dot_icon(color: QColor) -> QIcon:
    """Menu bar dot in the active laser color, so the state is visible."""
    size = 22
    pm = QPixmap(size * 2, size * 2)
    pm.setDevicePixelRatio(2.0)
    pm.fill(Qt.GlobalColor.transparent)

    painter = QPainter(pm)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    center = QPointF(size, size)
    r, g, b = color.red(), color.green(), color.blue()

    glow = QRadialGradient(center, size * 0.9)
    glow.setColorAt(0.0, QColor(r, g, b, 120))
    glow.setColorAt(1.0, QColor(r, g, b, 0))
    painter.setPen(Qt.PenStyle.NoPen)
    painter.setBrush(glow)
    painter.drawEllipse(center, size * 0.9, size * 0.9)

    painter.setBrush(QColor(r, g, b, 255))
    painter.drawEllipse(center, size * 0.42, size * 0.42)
    painter.end()

    return QIcon(pm)


# ── Controller ───────────────────────────────────────────────────────

class SFPoint:
    def __init__(self, app: QApplication):
        self.app = app
        self.canvas = LaserCanvas()
        self.hotkey = HotkeyListener()
        self.state = LASER_OFF
        self._permission_ok = True
        self._logo_icon = QIcon(QPixmap(LOGO_PATH))

        self._build_tray()
        self._wire_hotkeys()
        self._check_permission(first_run=True)

        # Watchdog: the moment the user grants the permission, wake the hotkey
        # up without making them hunt for a restart.
        self._watchdog = QTimer()
        self._watchdog.setInterval(2000)
        self._watchdog.timeout.connect(self._check_permission)
        self._watchdog.start()

        app.aboutToQuit.connect(self._on_quit)

    # --- tray ---

    def _build_tray(self):
        self.tray = QSystemTrayIcon()
        self.tray.setIcon(self._logo_icon)

        menu = QMenu()
        group = QActionGroup(menu)
        group.setExclusive(True)

        self.state_actions = {}
        for state in (LASER_OFF, LASER_AMBAR, LASER_MORADO):
            label = LASER_LABELS[state]
            text = f"{label}   ⌥P" if state == LASER_OFF else label
            action = menu.addAction(text)
            action.setCheckable(True)
            action.setChecked(state == LASER_OFF)
            group.addAction(action)
            action.triggered.connect(lambda _c, s=state: self.set_state(s))
            self.state_actions[state] = action

        menu.addSeparator()

        # Only shown when macOS is blocking the hotkey
        self.perm_action = menu.addAction("⚠️  Falta permiso: Monitorizacion de entrada")
        self.perm_action.triggered.connect(self._on_fix_permission)
        self.perm_action.setVisible(False)

        self.restart_action = menu.addAction("Reiniciar SFPoint")
        self.restart_action.triggered.connect(_restart_app)

        login_action = menu.addAction("Iniciar con macOS")
        login_action.setCheckable(True)
        login_action.setChecked(_is_launch_at_login())
        login_action.triggered.connect(lambda checked: _set_launch_at_login(checked))

        menu.addSeparator()
        menu.addAction("Salir").triggered.connect(self.app.quit)

        self.tray.setContextMenu(menu)
        self.tray.show()

    # --- hotkeys ---

    def _wire_hotkeys(self):
        self.hotkey.cycle_requested.connect(
            self.cycle, Qt.ConnectionType.QueuedConnection)
        self.hotkey.off_requested.connect(
            lambda: self.set_state(LASER_OFF), Qt.ConnectionType.QueuedConnection)
        self.hotkey.start()

    # --- state ---

    def cycle(self):
        self.set_state({
            LASER_OFF: LASER_AMBAR,
            LASER_AMBAR: LASER_MORADO,
            LASER_MORADO: LASER_OFF,
        }[self.state])

    def set_state(self, state: int):
        self.state = state
        self.canvas.set_state(state)
        self.state_actions[state].setChecked(True)

        if state == LASER_OFF:
            self.tray.setIcon(self._logo_icon)
            self.tray.setToolTip("SFPoint — ⌥P para el laser")
        else:
            color = LASER_COLORS[state]
            self.tray.setIcon(_dot_icon(color))
            self.tray.setToolTip(f"SFPoint — laser {LASER_LABELS[state].lower()}")

    # --- permissions ---

    def _check_permission(self, first_run: bool = False):
        ok = has_input_monitoring()
        if ok == self._permission_ok and not first_run:
            return

        was_broken = not self._permission_ok
        self._permission_ok = ok
        self.perm_action.setVisible(not ok)

        if ok:
            if was_broken:
                # Granted while running — restart the tap so ⌥P works right now
                self.hotkey.start()
            return

        if first_run:
            # Native prompt. macOS only shows it once per app signature, so if
            # it returns False we speak up ourselves instead of going silent.
            if request_input_monitoring():
                self._permission_ok = True
                self.perm_action.setVisible(False)
                return
            QTimer.singleShot(400, self._warn_missing_permission)

    def _warn_missing_permission(self):
        box = QMessageBox()
        box.setIcon(QMessageBox.Icon.Warning)
        box.setWindowFlag(Qt.WindowType.WindowStaysOnTopHint, True)
        box.setText("SFPoint no puede escuchar ⌥P")
        box.setInformativeText(
            "macOS le esta negando el permiso de Monitorizacion de entrada.\n\n"
            "Mientras tanto el laser SI funciona desde el icono de la barra de menu.\n\n"
            "Para arreglarlo: activa SFPoint en Ajustes > Privacidad y Seguridad > "
            "Monitorizacion de entrada. Si ya aparece activado, quitalo con el boton "
            "menos y vuelve a agregarlo."
        )
        box.setDetailedText(
            "Si el permiso quedo pegado despues de reconstruir la app, el registro "
            "guardado ya no coincide con la firma. Se limpia con:\n\n"
            f"  {repair_command(BUNDLE_ID)}\n\n"
            "y despues se reinicia SFPoint."
        )
        open_btn = box.addButton("Abrir Ajustes", QMessageBox.ButtonRole.AcceptRole)
        box.addButton("Despues", QMessageBox.ButtonRole.RejectRole)
        box.exec()
        if box.clickedButton() is open_btn:
            open_settings_pane()

    def _on_fix_permission(self):
        open_settings_pane()
        self._warn_missing_permission()

    # --- shutdown ---

    def _on_quit(self):
        self.hotkey.stop()
        self.canvas.shutdown()


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    sfpoint = SFPoint(app)  # noqa: F841 — kept alive for the app's lifetime

    # Menu bar only, no Dock icon (must run after the tray exists)
    try:
        import AppKit
        AppKit.NSApp.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)
    except Exception:
        pass

    print("SFPoint running — ⌥P cicla: apagado → ambar → morado. Esc apaga.")
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
