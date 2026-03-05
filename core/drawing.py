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
    LASER_COLOR,
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
        """Draw ambar laser pointer — Google Slides style with light trail."""
        painter.setPen(Qt.PenStyle.NoPen)

        # Ambar color components
        lr, lg, lb = LASER_COLOR.red(), LASER_COLOR.green(), LASER_COLOR.blue()

        # Light trail — connected smooth glow that fades
        n = len(trail)
        if n >= 2:
            for i in range(1, n):
                t = (i + 1) / n  # 0→1 (oldest→newest)
                alpha = int(t * t * 160)  # quadratic for smooth Google Slides feel
                width = 2.0 + t * 6.0
                pen = QPen(QColor(lr, lg, lb, alpha), width,
                           Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap)
                painter.setPen(pen)
                painter.drawLine(
                    QPointF(*trail[i - 1]),
                    QPointF(*trail[i]),
                )
            painter.setPen(Qt.PenStyle.NoPen)

        if not pos:
            return

        px, py = pos

        # Outer glow — warm ambar halo
        glow = QRadialGradient(QPointF(px, py), LASER_GLOW_RADIUS)
        glow.setColorAt(0.0, QColor(lr, lg, lb, 90))
        glow.setColorAt(0.5, QColor(lr, lg, lb, 40))
        glow.setColorAt(1.0, QColor(lr, lg, lb, 0))
        painter.setBrush(glow)
        painter.drawEllipse(QPointF(px, py), LASER_GLOW_RADIUS, LASER_GLOW_RADIUS)

        # Inner dot — bright center with white core
        dot = QRadialGradient(QPointF(px, py), LASER_DOT_RADIUS)
        dot.setColorAt(0.0, QColor(255, 255, 255, 255))
        dot.setColorAt(0.25, QColor(255, 220, 100, 255))
        dot.setColorAt(0.6, QColor(lr, lg, lb, 240))
        dot.setColorAt(1.0, QColor(lr, lg, lb, 160))
        painter.setBrush(dot)
        painter.drawEllipse(QPointF(px, py), LASER_DOT_RADIUS, LASER_DOT_RADIUS)

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
