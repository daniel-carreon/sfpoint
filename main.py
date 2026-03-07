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
    hotkey.laser_toggled.connect(
        lambda on: _on_laser_toggled(canvas, toolbar, on),
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


def _on_laser_toggled(canvas: CanvasWidget, toolbar: ToolbarWidget, on: bool):
    canvas.set_laser(on)
    if on:
        toolbar.update_tool("laser")
        toolbar.set_active(True)
    elif not canvas.is_active:
        toolbar.set_active(False)


def _on_context_tool(canvas: CanvasWidget, toolbar: ToolbarWidget, hotkey, tool: str):
    from config import TOOL_LASER
    if tool == TOOL_LASER:
        # Toggle laser
        new_state = not canvas.is_laser_active
        canvas.set_laser(new_state)
        if new_state:
            toolbar.update_tool("laser")
            toolbar.set_active(True)
        elif not canvas.is_active:
            toolbar.set_active(False)
        # Sync hotkey internal state
        hotkey._laser_on = new_state
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


def _on_context_color(canvas: CanvasWidget, toolbar: ToolbarWidget, idx: int):
    canvas.set_color_index(idx)
    toolbar.update_color(idx)


def _on_context_stroke(canvas: CanvasWidget, toolbar: ToolbarWidget, width: float):
    canvas.set_stroke_width(width)
    toolbar.update_stroke(width)


if __name__ == "__main__":
    main()
