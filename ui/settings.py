"""Settings panel — shows shortcuts, allows rebinding."""

from ctypes import c_void_p
import AppKit
import objc
from PyQt6.QtWidgets import QWidget, QApplication, QVBoxLayout, QHBoxLayout, QLabel, QPushButton
from PyQt6.QtCore import Qt, pyqtSignal, QTimer
from PyQt6.QtGui import QColor, QFont, QPainter, QPainterPath
from config import (
    TOOL_SHORTCUTS, SHORTCUT_HIDE_TOOLBAR, SHORTCUT_SETTINGS,
    TOOL_ARROW, TOOL_RECT, TOOL_CIRCLE, TOOL_FREEHAND,
    TOOL_TEXT, TOOL_LASER,
    COLOR_MORADO, COLOR_AMBAR,
    save_shortcuts, load_shortcuts,
)


TOOL_DISPLAY = {
    TOOL_ARROW: "Arrow",
    TOOL_RECT: "Rectangle",
    TOOL_CIRCLE: "Circle",
    TOOL_FREEHAND: "Freehand",
    TOOL_TEXT: "Text",
    TOOL_LASER: "Pointer",
}


class ShortcutButton(QPushButton):
    """A button that captures a single key press for rebinding."""

    key_captured = pyqtSignal(str, str)  # (tool, new_key)

    def __init__(self, tool: str, current_key: str):
        super().__init__(f"Ctrl + {current_key.upper()}")
        self._tool = tool
        self._current_key = current_key
        self._listening = False
        self.setFixedWidth(100)
        self.setFixedHeight(28)
        self.setStyleSheet(self._normal_style())
        self.clicked.connect(self._start_listening)

    def _normal_style(self) -> str:
        return """
            QPushButton {
                background: rgba(255,255,255,0.08);
                color: #e0e0e0;
                border: 1px solid rgba(255,255,255,0.15);
                border-radius: 6px;
                font-size: 12px;
                font-weight: 500;
                padding: 2px 8px;
            }
            QPushButton:hover {
                background: rgba(139,92,246,0.2);
                border-color: rgba(139,92,246,0.4);
            }
        """

    def _listening_style(self) -> str:
        return """
            QPushButton {
                background: rgba(245,158,11,0.2);
                color: #F59E0B;
                border: 1px solid rgba(245,158,11,0.5);
                border-radius: 6px;
                font-size: 12px;
                font-weight: 600;
                padding: 2px 8px;
            }
        """

    def _start_listening(self):
        self._listening = True
        self.setText("Press key...")
        self.setStyleSheet(self._listening_style())
        self.setFocus()

    def keyPressEvent(self, event):
        if not self._listening:
            super().keyPressEvent(event)
            return
        text = event.text()
        if text and text.isalpha():
            new_key = text.lower()
            self._current_key = new_key
            self.setText(f"Ctrl + {new_key.upper()}")
            self._listening = False
            self.setStyleSheet(self._normal_style())
            self.key_captured.emit(self._tool, new_key)
        elif event.key() == Qt.Key.Key_Escape:
            self.setText(f"Ctrl + {self._current_key.upper()}")
            self._listening = False
            self.setStyleSheet(self._normal_style())


class SettingsPanel(QWidget):
    """Floating settings panel showing all shortcuts."""

    shortcuts_changed = pyqtSignal(dict)  # emits new shortcuts map

    def __init__(self):
        super().__init__()
        self._shortcuts = load_shortcuts()
        self._buttons: dict[str, ShortcutButton] = {}

        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFixedSize(280, 340)

        self._build_ui()
        self._position_on_screen()

    def _position_on_screen(self):
        screen = QApplication.primaryScreen()
        if screen:
            geo = screen.availableGeometry()
            x = geo.center().x() - self.width() // 2
            y = geo.center().y() - self.height() // 2
            self.move(x, y)

    def showEvent(self, event):
        super().showEvent(event)
        try:
            ns_view = objc.objc_object(c_void_p=c_void_p(self.winId().__int__()))
            ns_window = ns_view.window()
            ns_window.setLevel_(AppKit.NSFloatingWindowLevel + 2)
            ns_window.setStyleMask_(
                ns_window.styleMask() | AppKit.NSWindowStyleMaskNonactivatingPanel
            )
        except Exception:
            pass

    def _build_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(6)

        # Title
        title = QLabel("SFPoint Settings")
        title.setStyleSheet("color: white; font-size: 15px; font-weight: 700;")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title)

        subtitle = QLabel("Click a shortcut to rebind")
        subtitle.setStyleSheet("color: rgba(255,255,255,0.5); font-size: 11px;")
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(subtitle)
        layout.addSpacing(8)

        # Tool shortcuts
        tool_order = [TOOL_ARROW, TOOL_RECT, TOOL_CIRCLE, TOOL_FREEHAND, TOOL_TEXT, TOOL_LASER]
        reverse_shortcuts = {v: k for k, v in self._shortcuts.items()}

        for tool in tool_order:
            key = reverse_shortcuts.get(tool, "?")
            row = QHBoxLayout()
            row.setSpacing(8)

            label = QLabel(TOOL_DISPLAY.get(tool, tool))
            label.setStyleSheet("color: rgba(255,255,255,0.8); font-size: 12px;")
            label.setFixedWidth(80)
            row.addWidget(label)

            btn = ShortcutButton(tool, key)
            btn.key_captured.connect(self._on_key_captured)
            self._buttons[tool] = btn
            row.addWidget(btn)
            row.addStretch()

            layout.addLayout(row)

        layout.addSpacing(8)

        # Fixed shortcuts (not editable)
        fixed_label = QLabel("Fixed Shortcuts")
        fixed_label.setStyleSheet("color: rgba(255,255,255,0.4); font-size: 11px; font-weight: 600;")
        layout.addWidget(fixed_label)

        for name, shortcut in [("Hide Toolbar", "Ctrl+H"), ("Settings", "Ctrl+S"),
                                ("Undo", "Cmd+Z"), ("Clear All", "Cmd+Shift+Z"), ("Deactivate", "Esc")]:
            row = QHBoxLayout()
            lbl = QLabel(name)
            lbl.setStyleSheet("color: rgba(255,255,255,0.5); font-size: 11px;")
            lbl.setFixedWidth(80)
            row.addWidget(lbl)
            key_lbl = QLabel(shortcut)
            key_lbl.setStyleSheet("color: rgba(255,255,255,0.35); font-size: 11px;")
            row.addWidget(key_lbl)
            row.addStretch()
            layout.addLayout(row)

        layout.addStretch()

        # Close button
        close_btn = QPushButton("Close")
        close_btn.setFixedHeight(30)
        close_btn.setStyleSheet("""
            QPushButton {
                background: rgba(139,92,246,0.3);
                color: white;
                border: 1px solid rgba(139,92,246,0.5);
                border-radius: 8px;
                font-size: 12px;
                font-weight: 600;
            }
            QPushButton:hover {
                background: rgba(139,92,246,0.5);
            }
        """)
        close_btn.clicked.connect(self.hide)
        layout.addWidget(close_btn)

    def _on_key_captured(self, tool: str, new_key: str):
        # Remove old mapping for this tool
        old_keys = [k for k, v in self._shortcuts.items() if v == tool]
        for k in old_keys:
            del self._shortcuts[k]
        # Remove conflict if new_key was assigned to another tool
        if new_key in self._shortcuts:
            conflicting_tool = self._shortcuts[new_key]
            del self._shortcuts[new_key]
            # Update conflicting button to show "?"
            if conflicting_tool in self._buttons:
                self._buttons[conflicting_tool].setText("Ctrl + ?")
        # Assign
        self._shortcuts[new_key] = tool
        save_shortcuts(self._shortcuts)
        self.shortcuts_changed.emit(dict(self._shortcuts))

    def paintEvent(self, _event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()

        # Dark glass background
        path = QPainterPath()
        path.addRoundedRect(0.0, 0.0, float(w), float(h), 16.0, 16.0)
        painter.fillPath(path, QColor(20, 20, 25, 240))

        # Border
        from PyQt6.QtGui import QPen
        painter.setPen(QPen(QColor(139, 92, 246, 60), 1.0))
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRoundedRect(0, 0, w, h, 16, 16)

        painter.end()

    def toggle(self):
        if self.isVisible():
            self.hide()
        else:
            self._shortcuts = load_shortcuts()
            self.show()
            self.raise_()

    def keyPressEvent(self, event):
        if event.key() == Qt.Key.Key_Escape:
            self.hide()
        else:
            super().keyPressEvent(event)
