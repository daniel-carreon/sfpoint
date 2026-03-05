"""SFPoint — Screen Annotation Tool.

Ctrl+key toggles annotation tools on/off.
Ctrl+A=arrow, Ctrl+R=rect, Ctrl+C=circle, Ctrl+F=freehand,
Ctrl+T=text, Ctrl+P=pointer, Ctrl+H=hide toolbar, Ctrl+S=settings.
Esc=deactivate, Cmd+Z=undo, Cmd+Shift+Z=clear all.
"""

import signal
import sys
from PyQt6.QtWidgets import QApplication
from PyQt6.QtCore import Qt
from core.hotkey import HotkeyListener
from ui.canvas import CanvasWidget
from ui.toolbar import ToolbarWidget
from ui.settings import SettingsPanel


def main():
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    canvas = CanvasWidget()
    toolbar = ToolbarWidget()
    settings = SettingsPanel()
    hotkey = HotkeyListener()

    # --- Connect signals (all QueuedConnection for thread safety) ---

    hotkey.tool_toggled.connect(
        lambda tool: _on_tool_toggled(canvas, toolbar, tool),
        Qt.ConnectionType.QueuedConnection,
    )
    hotkey.deactivated.connect(
        lambda: _on_deactivated(canvas, toolbar),
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

    # Show UI
    canvas.show()
    toolbar.show()

    hotkey.start()

    print("SFPoint running.")
    print("  Ctrl+A=arrow  Ctrl+R=rect  Ctrl+C=circle  Ctrl+F=freehand")
    print("  Ctrl+T=text   Ctrl+P=pointer")
    print("  Ctrl+H=hide toolbar  Ctrl+S=settings")
    print("  Cmd+Z=undo  Cmd+Shift+Z=clear  Esc=deactivate")
    print("  Ctrl+C to quit (when no tool active)")

    exit_code = app.exec()
    hotkey.stop()
    sys.exit(exit_code)


def _on_tool_toggled(canvas: CanvasWidget, toolbar: ToolbarWidget, tool: str):
    canvas.set_tool(tool)
    canvas.set_active(True)
    toolbar.update_tool(tool)
    toolbar.set_active(True)


def _on_deactivated(canvas: CanvasWidget, toolbar: ToolbarWidget):
    canvas.set_active(False)
    toolbar.set_active(False)


if __name__ == "__main__":
    main()
