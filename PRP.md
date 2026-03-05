# PRP-001: SFPoint — Screen Annotation Tool (Presentify Alternative)

> **Status**: COMPLETED
> **Date**: 2026-03-05
> **Author**: Claude Opus 4.6
> **Project**: sfpoint

---

## Objective

Build a macOS desktop screen annotation tool in Python that draws temporary arrows, rectangles, circles, freehand lines, text, and a laser pointer on a transparent fullscreen overlay. Activated via global hotkeys — hold a modifier key + tool letter to draw, release to return to normal interaction. Annotations auto-fade after a configurable delay. Includes a floating mini-toolbar for tool/color selection.

This is a fully functional replacement for Presentify ($7 one-time) built from scratch, with SF brand colors (morado + ambar) and full customization.

---

## Why

| Current Problem | Proposed Solution |
|-----------------|-------------------|
| Presentify costs $7 and is closed-source | Own app, free, fully customizable |
| Limited to their color palette | SF brand colors (morado #8B5CF6, ambar #F59E0B) baked in |
| No laser pointer like Google Slides | Built-in laser pointer with glow trail |
| Can't extend or integrate with other tools | Python + PyQt6, same stack as SFlow |
| One-size-fits-all shortcuts | Custom hotkeys, configurable fade times |

**Value**: Free, branded, extensible annotation tool for teaching and presentations.

---

## What

### Expected Behavior

1. Launch `smark` — a small floating toolbar appears (bottom-center, similar to SFlow pill)
2. User holds **fn** (or configured modifier) — fullscreen transparent overlay activates
3. While holding fn, press a tool key:
   - `A` = arrow
   - `R` = rectangle
   - `C` = circle/ellipse
   - `F` = freehand draw
   - `T` = text (type then Enter to place)
   - `L` = laser pointer (red dot with glow trail, no persistence)
   - `H` = highlighter (semi-transparent thick stroke)
4. Draw with mouse while holding modifier + tool key
5. Release modifier — overlay deactivates, clicks pass through again
6. Annotations **auto-fade** after configurable delay (default 3 seconds)
7. Laser pointer leaves a fading trail but never persists
8. Toolbar shows current tool, color, and stroke size
9. Color shortcuts: `1` = morado (brand), `2` = ambar (brand), `3` = red, `4` = green, `5` = white
10. `Cmd+Z` undoes last annotation, `Cmd+Shift+Z` clears all
11. `Esc` cancels current drawing and deactivates overlay

### Success Criteria
- [ ] Overlay covers full screen without stealing focus from other apps
- [ ] Click-through when NOT drawing (overlay is invisible to mouse)
- [ ] Click-capture when drawing (overlay captures mouse for shapes)
- [ ] All 7 tools work: arrow, rect, circle, freehand, text, laser, highlighter
- [ ] Annotations auto-fade with smooth opacity animation
- [ ] Laser pointer has glowing dot + fading trail
- [ ] Brand colors as defaults (morado + ambar)
- [ ] Mini toolbar shows state without being intrusive
- [ ] Works in all Spaces/desktops, survives fullscreen apps
- [ ] No focus stealing — cursor stays in whatever app user is using
- [ ] Undo/clear shortcuts work

---

## Required Context

### Documentation & References
```yaml
- doc: https://doc.qt.io/qtforpython-6/
  critical: "QPainter for drawing shapes. QGraphicsOpacityEffect for fade. WA_TranslucentBackground for transparent overlay."

- doc: https://pyobjc.readthedocs.io/
  critical: "NSFloatingWindowLevel + NSWindowStyleMaskNonactivatingPanel. setIgnoresMouseEvents_ for click-through toggle."

- doc: https://pynput.readthedocs.io/en/latest/keyboard.html
  critical: "Global hotkeys. fn key detection on macOS. Same pattern as SFlow."

- reference: /Users/danielcarreon/Developer/software/sflow/ui/pill_widget.py
  critical: "Reuse PyObjC floating window setup (_setup_native_macos). Proven pattern."

- reference: /Users/danielcarreon/Developer/software/sflow/core/hotkey.py
  critical: "Reuse pynput listener pattern with QueuedConnection signals."
```

### Architecture
```
smark/
├── main.py                 # Entry point — wires hotkey + overlay + toolbar
├── config.py               # Colors, hotkeys, fade timing, stroke sizes
├── core/
│   ├── __init__.py
│   ├── hotkey.py           # Global hotkey detection (modifier + tool keys)
│   └── drawing.py          # Shape engine (Arrow, Rect, Circle, Freehand, Text, Laser, Highlighter)
├── ui/
│   ├── __init__.py
│   ├── canvas.py           # Fullscreen transparent overlay (click-through toggle)
│   └── toolbar.py          # Mini floating toolbar (tool + color indicator)
├── logo.png                # SF brand logo (full size)
├── logo_small.png          # SF brand logo (for toolbar, ~22x22)
├── requirements.txt
└── .gitignore
```

### Data Model

No persistent storage needed. All annotations are ephemeral (in-memory list, auto-removed on fade).

```python
@dataclass
class Annotation:
    tool: str           # "arrow" | "rect" | "circle" | "freehand" | "text" | "highlighter"
    points: list        # [(x,y), ...] — start/end for shapes, all points for freehand
    color: QColor       # RGBA
    stroke_width: float
    text: str           # Only for text tool
    created_at: float   # time.time() for fade calculation
    opacity: float      # 1.0 → 0.0 during fade
```

---

## Implementation Blueprint

### Phase 0: Project Setup
**Objective**: Create project structure and install dependencies

- [ ] Create directory structure (`core/`, `ui/`)
- [ ] Create `requirements.txt`: `PyQt6 pynput pyobjc-framework-Cocoa numpy`
- [ ] Create virtual environment and install deps
- [ ] Copy logo files from SFlow (or SF brand assets)
- [ ] Create `.gitignore`

**Validation**: `python3 -c "import PyQt6, pynput, AppKit; print('OK')"`

### Phase 1: Config
**Objective**: Centralized configuration with brand colors

- [ ] Create `config.py` with:
  - Brand colors: MORADO `#8B5CF6`, AMBAR `#F59E0B`, plus red/green/white
  - Tool hotkeys: A/R/C/F/T/L/H
  - Modifier key: fn (Key.fn on macOS, fallback to right_shift)
  - Fade delay: 3.0 seconds (configurable)
  - Fade duration: 0.5 seconds
  - Stroke widths: thin (2), medium (3), thick (5), highlighter (20)
  - Laser config: dot radius (8), trail length (15 points), glow radius (20)
  - Toolbar dimensions (reuse SFlow pill pattern)

**Validation**: Import config, print all values

### Phase 2: Fullscreen Transparent Overlay (Canvas)
**Objective**: Transparent fullscreen window with click-through toggle

This is the most critical component. The overlay must:
- Cover the entire screen with a fully transparent window
- Pass through ALL mouse/keyboard events when inactive (click-through)
- Capture mouse events when active (drawing mode)
- Float above everything including fullscreen apps
- Never steal focus

- [ ] Create `ui/canvas.py` — `CanvasWidget(QWidget)`
- [ ] Window flags: FramelessWindowHint + WindowStaysOnTopHint + Tool + WindowDoesNotAcceptFocus
- [ ] Attributes: WA_TranslucentBackground + WA_ShowWithoutActivating
- [ ] Geometry: full screen (primary screen geometry)
- [ ] PyObjC native setup (reuse from SFlow pill_widget.py):
  - `NSFloatingWindowLevel` — above all windows
  - `NSWindowStyleMaskNonactivatingPanel` — never steal focus
  - `setHidesOnDeactivate_(False)` — always visible
  - `NSWindowCollectionBehaviorCanJoinAllSpaces` — all desktops
- [ ] **Click-through toggle** via PyObjC:
  - `ns_window.setIgnoresMouseEvents_(True)` — inactive (clicks pass through)
  - `ns_window.setIgnoresMouseEvents_(False)` — active (drawing mode)
- [ ] `paintEvent()` — renders all annotations from the annotation list
- [ ] `mousePressEvent/mouseMoveEvent/mouseReleaseEvent` — captures drawing input
- [ ] QTimer at 60 FPS for fade animation (decrements opacity, removes expired annotations)

**Key PyObjC for click-through:**
```python
def set_drawing_mode(self, active: bool):
    ns_view = objc.objc_object(c_void_p=c_void_p(self.winId().__int__()))
    ns_window = ns_view.window()
    ns_window.setIgnoresMouseEvents_(not active)
    if active:
        # Raise to ensure we capture input
        ns_window.orderFrontRegardless()
```

**Validation**: Overlay appears, is fully transparent, clicks pass through. Toggle drawing mode — clicks captured.

### Phase 3: Drawing Engine (Shapes)
**Objective**: Render all shape types with QPainter

- [ ] Create `core/drawing.py` with `Annotation` dataclass
- [ ] Create `ShapeRenderer` class with static methods per shape:
  - `draw_arrow(painter, start, end, color, width)` — line + arrowhead (filled triangle)
  - `draw_rect(painter, start, end, color, width)` — rectangle outline
  - `draw_circle(painter, start, end, color, width)` — ellipse inscribed in bounding rect
  - `draw_freehand(painter, points, color, width)` — smooth polyline (QPainterPath with cubicTo)
  - `draw_text(painter, pos, text, color, size)` — text at position
  - `draw_highlighter(painter, points, color, width)` — thick semi-transparent stroke
  - `draw_laser(painter, pos, trail, color)` — glowing dot + fading trail
- [ ] Arrow head calculation: 12px length, 25-degree angle from shaft
- [ ] Freehand smoothing: Catmull-Rom or cubic bezier through points

**QPainter arrow head pattern:**
```python
import math

def draw_arrow(painter, p1, p2, color, width):
    painter.setPen(QPen(color, width, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
    painter.drawLine(p1, p2)

    # Arrowhead
    angle = math.atan2(p2.y() - p1.y(), p2.x() - p1.x())
    head_len = 14
    head_angle = math.radians(25)

    left = QPointF(
        p2.x() - head_len * math.cos(angle - head_angle),
        p2.y() - head_len * math.sin(angle - head_angle)
    )
    right = QPointF(
        p2.x() - head_len * math.cos(angle + head_angle),
        p2.y() - head_len * math.sin(angle + head_angle)
    )

    path = QPainterPath()
    path.moveTo(p2)
    path.lineTo(left)
    path.lineTo(right)
    path.closeSubpath()
    painter.fillPath(path, color)
```

**Validation**: Each shape renders correctly on the canvas

### Phase 4: Laser Pointer
**Objective**: Glowing dot that follows cursor with fading trail

- [ ] Laser is NOT an annotation — it's a real-time cursor effect
- [ ] Dot: filled circle (8px radius) with radial gradient (bright center → transparent edge)
- [ ] Glow: larger circle (20px radius) with low-opacity radial gradient
- [ ] Trail: last N positions (15), each drawn as a dot with decreasing opacity and size
- [ ] Trail updated on every mouseMoveEvent when laser tool is active
- [ ] No persistence — trail disappears when modifier released

**Laser glow pattern:**
```python
def draw_laser(painter, pos, trail):
    # Trail (oldest → newest, decreasing opacity)
    for i, (tx, ty) in enumerate(trail):
        t = i / len(trail)  # 0.0 oldest → 1.0 newest
        alpha = int(t * 120)
        radius = 2 + t * 4
        painter.setBrush(QColor(255, 50, 50, alpha))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawEllipse(QPointF(tx, ty), radius, radius)

    # Glow
    gradient = QRadialGradient(pos, 20)
    gradient.setColorAt(0.0, QColor(255, 80, 80, 100))
    gradient.setColorAt(1.0, QColor(255, 50, 50, 0))
    painter.setBrush(gradient)
    painter.drawEllipse(pos, 20, 20)

    # Dot
    gradient2 = QRadialGradient(pos, 8)
    gradient2.setColorAt(0.0, QColor(255, 255, 255, 255))
    gradient2.setColorAt(0.3, QColor(255, 80, 80, 255))
    gradient2.setColorAt(1.0, QColor(255, 50, 50, 180))
    painter.setBrush(gradient2)
    painter.drawEllipse(pos, 8, 8)
```

**Validation**: Laser dot follows cursor smoothly, trail fades, disappears on release

### Phase 5: Global Hotkeys
**Objective**: Modifier + tool key activates drawing mode

- [ ] Create `core/hotkey.py` — reuse pynput pattern from SFlow
- [ ] Signals: `activated(tool: str)`, `deactivated()`, `color_changed(index: int)`, `undo()`, `clear()`
- [ ] Modifier detection: fn key (Key.fn on macOS)
  - **Fallback**: If fn isn't detectable by pynput, use right_shift or right_cmd
- [ ] While modifier held:
  - `A` → activate with "arrow"
  - `R` → activate with "rect"
  - `C` → activate with "circle"
  - `F` → activate with "freehand"
  - `T` → activate with "text"
  - `L` → activate with "laser"
  - `H` → activate with "highlighter"
  - `1-5` → change color
  - `[` / `]` → decrease/increase stroke width
- [ ] Modifier released → deactivate (canvas goes click-through)
- [ ] `Cmd+Z` → undo last annotation
- [ ] `Cmd+Shift+Z` → clear all annotations
- [ ] Esc → cancel current drawing + deactivate

**CRITICAL**: Same QueuedConnection threading pattern as SFlow. pynput emits from its own thread.

**Validation**: Hotkeys detected in any app, correct tool activated

### Phase 6: Auto-Fade System
**Objective**: Annotations smoothly fade out after delay

- [ ] Each annotation has `created_at` timestamp and `opacity` (1.0)
- [ ] QTimer at 60 FPS checks all annotations:
  - If `time.time() - created_at > FADE_DELAY`: start fading
  - Decrement opacity: `opacity -= (1.0 / FADE_DURATION) / 60`
  - If `opacity <= 0`: remove from list
- [ ] Canvas `paintEvent` uses annotation's opacity for all QPainter operations
- [ ] Laser trail has its own fade (position-based, not time-based)

**Validation**: Draw an arrow, wait 3 seconds, verify smooth fade over 0.5 seconds

### Phase 7: Floating Toolbar
**Objective**: Minimal toolbar showing current tool and color

- [ ] Create `ui/toolbar.py` — reuse SFlow pill pattern
- [ ] Same PyObjC floating window setup (no focus steal)
- [ ] Layout: `[Logo] [Tool Icon] [Color Dot] [Stroke Preview]`
- [ ] Tool icons: simple QPainter drawings (arrow icon, rect icon, etc.)
- [ ] Color dot: filled circle with current color
- [ ] Draggable (reuse SFlow drag code)
- [ ] Semi-transparent dark background (same style as SFlow pill)
- [ ] Updates when tool/color changes via signals

**Validation**: Toolbar appears, shows correct state, draggable, no focus steal

### Phase 8: Integration (main.py)
**Objective**: Wire all modules together

- [ ] Create `main.py` — QApplication + Canvas + Toolbar + HotkeyListener
- [ ] Signal flow:
  - `hotkey.activated(tool)` → `canvas.set_drawing_mode(True)` + `canvas.set_tool(tool)` + `toolbar.update_tool(tool)`
  - `hotkey.deactivated()` → `canvas.set_drawing_mode(False)` + finalize current shape
  - `hotkey.color_changed(idx)` → `canvas.set_color(colors[idx])` + `toolbar.update_color()`
  - `hotkey.undo()` → `canvas.undo()`
  - `hotkey.clear()` → `canvas.clear_all()`
- [ ] ALL cross-thread signals use `Qt.ConnectionType.QueuedConnection`
- [ ] `signal.signal(signal.SIGINT, signal.SIG_DFL)` for clean Ctrl+C exit
- [ ] Canvas starts with click-through enabled (inactive)
- [ ] Toolbar starts visible, canvas overlay starts fullscreen but transparent

**Validation**: Full E2E — hold modifier + A, draw arrow, release, arrow fades. Laser follows cursor. Toolbar updates.

---

## Validation Loop

### Level 1: Imports
```bash
source venv/bin/activate
python3 -c "import PyQt6, pynput, AppKit; print('All OK')"
```

### Level 2: Each Module
```bash
python3 -c "from core.drawing import Annotation, ShapeRenderer; print('Drawing OK')"
python3 -c "from ui.canvas import CanvasWidget; print('Canvas OK')"
python3 -c "from ui.toolbar import ToolbarWidget; print('Toolbar OK')"
python3 -c "from core.hotkey import HotkeyListener; print('Hotkey OK')"
```

### Level 3: Integration
```bash
python3 main.py
# Verify: overlay transparent, hotkey activates, shapes draw, fade works, laser works
```

---

## Known Gotchas

```python
# CRITICAL: fn key may not be detectable by pynput on all macOS versions
# Fallback: use right_shift or right_cmd as modifier
# Test with: pynput.keyboard.Listener + print key to check fn detection

# CRITICAL: Click-through toggle via setIgnoresMouseEvents_
# When True: overlay is invisible to mouse (clicks pass through to apps below)
# When False: overlay captures mouse (drawing mode)
# MUST toggle correctly or user gets stuck unable to click anything

# CRITICAL: orderFrontRegardless() needed when entering drawing mode
# Without it, the overlay may not capture mouse if another window was focused

# CRITICAL: Same Qt signal threading as SFlow
# pynput emits from its own thread → MUST use QueuedConnection

# CRITICAL: Fullscreen overlay geometry must match screen exactly
# Use QApplication.primaryScreen().geometry() (not availableGeometry)
# availableGeometry excludes menu bar — we want to draw everywhere

# IMPORTANT: Semi-transparent shapes need careful QPainter composition
# Use QPainter.CompositionMode_SourceOver for proper alpha blending

# IMPORTANT: Text tool needs special handling — capture keyboard input
# While text tool active, fn modifier should NOT deactivate on key press
# Solution: text mode captures all keys until Enter (place) or Esc (cancel)

# IMPORTANT: Multi-monitor support
# For V1, target primary screen only. Multi-monitor is a V2 feature.

# IMPORTANT: macOS permissions — same as SFlow
# Accessibility + Input Monitoring required for pynput
```

---

## Anti-Patterns to Avoid

- DO NOT use a semi-transparent background tint on the overlay — must be fully transparent
- DO NOT leave click-through disabled after deactivation — user can't click anything
- DO NOT process drawing on secondary threads — QPainter must run on main thread
- DO NOT use Qt's window flags alone for macOS floating — use PyObjC (proven in SFlow)
- DO NOT forget to call `update()` after modifying annotations list
- DO NOT use pyautogui for any mouse/keyboard handling — use pynput (proven in SFlow)
- DO NOT create a new QPixmap per frame — paint directly on widget
- DO NOT use QGraphicsScene for this — overkill, plain QWidget + QPainter is cleaner
- DO NOT block the main thread with sleep/wait — use QTimer for all timing

---

## Brand Colors

```python
# SF Brand Palette
COLORS = {
    "morado":  QColor(139, 92, 246),     # #8B5CF6 — primary brand
    "ambar":   QColor(245, 158, 11),     # #F59E0B — secondary brand
    "red":     QColor(239, 68, 68),      # #EF4444 — alerts/emphasis
    "green":   QColor(34, 197, 94),      # #22C55E — success/highlight
    "white":   QColor(255, 255, 255),    # #FFFFFF — on dark backgrounds
}

# Default: morado
# Laser: always red (with white center glow)
```

---

## Dependencies

```bash
# No system dependencies needed (unlike SFlow which needs portaudio)

# Python (in virtual environment)
pip install PyQt6 pynput pyobjc-framework-Cocoa numpy
```

---

## Environment

- **Python**: 3.12+
- **macOS**: 15+ (requires Accessibility permissions)
- **Stack**: Python + PyQt6 + pynput + PyObjC
- **Cost**: $0 (vs $7 for Presentify)
- **Reused from SFlow**: Floating window pattern, hotkey pattern, pill UI pattern
