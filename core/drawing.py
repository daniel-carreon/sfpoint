"""Shape engine: Annotation dataclass + ShapeRenderer for all tools."""

import math
import time
from dataclasses import dataclass, field
from PyQt6.QtCore import Qt, QPointF, QRectF
from PyQt6.QtGui import (
    QPainter, QPen, QColor, QPainterPath, QFont,
    QRadialGradient,
)
from config import (
    ARROW_HEAD_LENGTH, ARROW_HEAD_ANGLE, TEXT_FONT_SIZE,
    LASER_DOT_RADIUS, LASER_GLOW_RADIUS, HIGHLIGHTER_OPACITY,
    LASER_COLOR, RIPPLE_MAX_RADIUS, RIPPLE_DURATION,
    COLOR_MORADO,
)


@dataclass
class Annotation:
    tool: str
    points: list = field(default_factory=list)
    color: QColor = field(default_factory=lambda: QColor(139, 92, 246))
    stroke_width: float = 3.0
    text: str = ""
    created_at: float = field(default_factory=time.time)
    opacity: float = 1.0


def _color_with_alpha(color: QColor, opacity: float) -> QColor:
    """Return a copy of color with opacity applied."""
    c = QColor(color)
    c.setAlphaF(min(color.alphaF() * opacity, 1.0))
    return c


class ShapeRenderer:
    """Static methods to render each tool's shape via QPainter."""

    @staticmethod
    def draw_arrow(painter: QPainter, ann: Annotation):
        if len(ann.points) < 2:
            return
        p1, p2 = QPointF(*ann.points[0]), QPointF(*ann.points[-1])
        color = _color_with_alpha(ann.color, ann.opacity)

        pen = QPen(color, ann.stroke_width, Qt.PenStyle.SolidLine,
                    Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
        painter.setPen(pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawLine(p1, p2)

        dx = p2.x() - p1.x()
        dy = p2.y() - p1.y()
        length = math.hypot(dx, dy)
        if length < 1:
            return
        angle = math.atan2(dy, dx)
        head_angle = math.radians(ARROW_HEAD_ANGLE)
        head_len = ARROW_HEAD_LENGTH

        left = QPointF(
            p2.x() - head_len * math.cos(angle - head_angle),
            p2.y() - head_len * math.sin(angle - head_angle),
        )
        right = QPointF(
            p2.x() - head_len * math.cos(angle + head_angle),
            p2.y() - head_len * math.sin(angle + head_angle),
        )

        path = QPainterPath()
        path.moveTo(p2)
        path.lineTo(left)
        path.lineTo(right)
        path.closeSubpath()
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(color)
        painter.fillPath(path, color)

    @staticmethod
    def draw_rect(painter: QPainter, ann: Annotation):
        if len(ann.points) < 2:
            return
        p1, p2 = ann.points[0], ann.points[-1]
        color = _color_with_alpha(ann.color, ann.opacity)

        pen = QPen(color, ann.stroke_width, Qt.PenStyle.SolidLine,
                    Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
        painter.setPen(pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)

        x = min(p1[0], p2[0])
        y = min(p1[1], p2[1])
        w = abs(p2[0] - p1[0])
        h = abs(p2[1] - p1[1])
        painter.drawRect(QRectF(x, y, w, h))

    @staticmethod
    def draw_circle(painter: QPainter, ann: Annotation):
        if len(ann.points) < 2:
            return
        p1, p2 = ann.points[0], ann.points[-1]
        color = _color_with_alpha(ann.color, ann.opacity)

        pen = QPen(color, ann.stroke_width, Qt.PenStyle.SolidLine,
                    Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
        painter.setPen(pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)

        x = min(p1[0], p2[0])
        y = min(p1[1], p2[1])
        w = abs(p2[0] - p1[0])
        h = abs(p2[1] - p1[1])
        painter.drawEllipse(QRectF(x, y, w, h))

    @staticmethod
    def draw_freehand(painter: QPainter, ann: Annotation):
        if len(ann.points) < 2:
            return
        color = _color_with_alpha(ann.color, ann.opacity)
        pen = QPen(color, ann.stroke_width, Qt.PenStyle.SolidLine,
                    Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
        painter.setPen(pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)

        path = QPainterPath()
        path.moveTo(*ann.points[0])

        if len(ann.points) == 2:
            path.lineTo(*ann.points[1])
        else:
            for i in range(1, len(ann.points) - 1):
                x0, y0 = ann.points[i]
                x1, y1 = ann.points[i + 1]
                cx = (x0 + x1) / 2.0
                cy = (y0 + y1) / 2.0
                path.quadTo(x0, y0, cx, cy)
            path.lineTo(*ann.points[-1])

        painter.drawPath(path)

    @staticmethod
    def draw_text(painter: QPainter, ann: Annotation):
        if not ann.text or len(ann.points) < 1:
            return
        color = _color_with_alpha(ann.color, ann.opacity)
        pos = QPointF(*ann.points[0])

        font = QFont(".AppleSystemUIFont", TEXT_FONT_SIZE)
        font.setBold(True)
        painter.setFont(font)
        painter.setPen(color)
        painter.drawText(pos, ann.text)

    @staticmethod
    def draw_highlighter(painter: QPainter, ann: Annotation):
        if len(ann.points) < 2:
            return
        color = QColor(ann.color)
        color.setAlphaF(HIGHLIGHTER_OPACITY * ann.opacity)

        pen = QPen(color, ann.stroke_width, Qt.PenStyle.SolidLine,
                    Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
        painter.setPen(pen)
        painter.setBrush(Qt.BrushStyle.NoBrush)

        path = QPainterPath()
        path.moveTo(*ann.points[0])
        for i in range(1, len(ann.points)):
            path.lineTo(*ann.points[i])
        painter.drawPath(path)

    @staticmethod
    def draw_laser(painter: QPainter, pos: tuple, trail: list):
        """Draw neon laser pointer with bloom glow and luminous trail."""
        painter.setPen(Qt.PenStyle.NoPen)

        lr, lg, lb = LASER_COLOR.red(), LASER_COLOR.green(), LASER_COLOR.blue()

        n = len(trail)
        if n >= 2:
            # Pass 1: Wide soft glow underneath (the "neon bleed")
            for i in range(1, n):
                t = (i + 1) / n
                alpha = int(t * t * 30)
                width = 4.0 + t * 10.0
                pen = QPen(QColor(lr, lg, lb, alpha), width,
                           Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap)
                painter.setPen(pen)
                painter.drawLine(QPointF(*trail[i - 1]), QPointF(*trail[i]))

            # Pass 2: Mid glow layer
            for i in range(1, n):
                t = (i + 1) / n
                alpha = int(t * t * 80)
                width = 2.0 + t * 4.0
                pen = QPen(QColor(lr, lg, lb, alpha), width,
                           Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap)
                painter.setPen(pen)
                painter.drawLine(QPointF(*trail[i - 1]), QPointF(*trail[i]))

            # Pass 3: Bright core line (hot white-ambar center)
            for i in range(1, n):
                t = (i + 1) / n
                # Blend from ambar to white toward the newest point
                r = lr + int((255 - lr) * t * 0.6)
                g = lg + int((240 - lg) * t * 0.4)
                b = lb + int((180 - lb) * t * 0.3)
                alpha = int(t * t * 200)
                width = 1.0 + t * 1.8
                pen = QPen(QColor(r, g, b, alpha), width,
                           Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap)
                painter.setPen(pen)
                painter.drawLine(QPointF(*trail[i - 1]), QPointF(*trail[i]))

            painter.setPen(Qt.PenStyle.NoPen)

        if not pos:
            return

        px, py = pos
        center = QPointF(px, py)
        painter.setPen(Qt.PenStyle.NoPen)

        # Use drawRect instead of drawEllipse — the radial gradient creates
        # the circular shape, but a rect has no curved edge to anti-alias.
        # This eliminates the dark fringe artifact entirely.
        full_r = LASER_GLOW_RADIUS * 2.5
        dot_stop = LASER_DOT_RADIUS / full_r
        glow_stop = LASER_GLOW_RADIUS / full_r
        bloom_stop = (LASER_GLOW_RADIUS * 2.0) / full_r

        grad = QRadialGradient(center, full_r)
        grad.setColorAt(0.0, QColor(255, 250, 220, 255))
        grad.setColorAt(dot_stop * 0.4, QColor(255, 220, 140, 240))
        grad.setColorAt(dot_stop * 0.7, QColor(lr, lg, lb, 210))
        grad.setColorAt(dot_stop, QColor(lr, lg, lb, 160))
        grad.setColorAt(glow_stop * 0.6, QColor(lr, lg, lb, 60))
        grad.setColorAt(glow_stop, QColor(lr, lg, lb, 25))
        grad.setColorAt(bloom_stop * 0.7, QColor(lr, lg, lb, 10))
        grad.setColorAt(bloom_stop, QColor(lr, lg, lb, 3))
        grad.setColorAt(1.0, QColor(lr, lg, lb, 0))

        painter.setBrush(grad)
        painter.drawRect(QRectF(px - full_r, py - full_r, full_r * 2, full_r * 2))

    @staticmethod
    def draw_ripple(painter: QPainter, pos: tuple, progress: float):
        """Draw expanding morado ripple on click. progress: 0..1."""
        if not pos or progress >= 1.0:
            return
        mr, mg, mb = COLOR_MORADO.red(), COLOR_MORADO.green(), COLOR_MORADO.blue()
        px, py = pos

        # Ease-out curve for smooth expansion
        ease = 1.0 - (1.0 - progress) ** 3
        radius = 3.0 + ease * RIPPLE_MAX_RADIUS

        # Crisp ring — starts strong, fades gracefully
        ring_alpha = int(200 * (1.0 - progress) ** 1.5)
        ring_width = 2.0 * (1.0 - progress * 0.6)
        painter.setPen(QPen(QColor(mr, mg, mb, ring_alpha), ring_width))
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawEllipse(QPointF(px, py), radius, radius)

        # Soft morado fill — visible but brief
        fill_alpha = int(80 * (1.0 - progress) ** 2.5)
        if fill_alpha > 2:
            grad = QRadialGradient(QPointF(px, py), radius)
            grad.setColorAt(0.0, QColor(mr, mg, mb, fill_alpha))
            grad.setColorAt(1.0, QColor(mr, mg, mb, 0))
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(grad)
            painter.drawEllipse(QPointF(px, py), radius, radius)

    @staticmethod
    def render(painter: QPainter, ann: Annotation):
        """Dispatch to the correct draw method."""
        dispatch = {
            "arrow": ShapeRenderer.draw_arrow,
            "rect": ShapeRenderer.draw_rect,
            "circle": ShapeRenderer.draw_circle,
            "freehand": ShapeRenderer.draw_freehand,
            "text": ShapeRenderer.draw_text,
            "highlighter": ShapeRenderer.draw_highlighter,
        }
        fn = dispatch.get(ann.tool)
        if fn:
            fn(painter, ann)
