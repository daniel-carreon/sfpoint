"""Laser renderer — neon dot with bloom, luminous trail, click shockwave.

Pure drawing functions. No state, no tools, no shapes.
"""

from PyQt6.QtCore import Qt, QPointF, QRectF
from PyQt6.QtGui import QPainter, QPen, QColor, QRadialGradient
from config import (
    LASER_DOT_RADIUS, LASER_GLOW_RADIUS,
    RIPPLE_MAX_RADIUS, COLOR_AMBAR, COLOR_MORADO,
)

# Padding used to compute dirty rects (keep in sync with the draw math below)
LASER_PAD = LASER_GLOW_RADIUS * 2.5 + 4.0
RIPPLE_PAD = RIPPLE_MAX_RADIUS * 1.6 + 10.0


def opposite_color(color: QColor) -> QColor:
    """Ripple is always the opposite brand color of the active laser."""
    return COLOR_MORADO if color == COLOR_AMBAR else COLOR_AMBAR


def draw_laser(painter: QPainter, pos: tuple | None, trail: list, color: QColor):
    """Neon laser pointer with bloom glow and luminous trail."""
    painter.setPen(Qt.PenStyle.NoPen)

    lr, lg, lb = color.red(), color.green(), color.blue()
    dot_diam = LASER_DOT_RADIUS * 2.0

    n = len(trail)
    if n >= 2:
        # Pass 1: wide soft glow underneath (the neon bleed)
        for i in range(1, n):
            t = (i + 1) / n
            pen = QPen(QColor(lr, lg, lb, int(t * t * 30)), t * dot_diam * 2.5,
                       Qt.PenStyle.SolidLine, Qt.PenCapStyle.FlatCap)
            painter.setPen(pen)
            painter.drawLine(QPointF(*trail[i - 1]), QPointF(*trail[i]))

        # Pass 2: mid glow layer
        for i in range(1, n):
            t = (i + 1) / n
            pen = QPen(QColor(lr, lg, lb, int(t * t * 80)), t * dot_diam * 1.1,
                       Qt.PenStyle.SolidLine, Qt.PenCapStyle.FlatCap)
            painter.setPen(pen)
            painter.drawLine(QPointF(*trail[i - 1]), QPointF(*trail[i]))

        # Pass 3: bright core line (hot center)
        for i in range(1, n):
            t = (i + 1) / n
            r = lr + int((255 - lr) * t * 0.6)
            g = lg + int((240 - lg) * t * 0.4)
            b = lb + int((180 - lb) * t * 0.3)
            pen = QPen(QColor(r, g, b, int(t * t * 200)), t * dot_diam * 0.6,
                       Qt.PenStyle.SolidLine, Qt.PenCapStyle.FlatCap)
            painter.setPen(pen)
            painter.drawLine(QPointF(*trail[i - 1]), QPointF(*trail[i]))

        painter.setPen(Qt.PenStyle.NoPen)

    if not pos:
        return

    px, py = pos
    center = QPointF(px, py)

    # Radial gradient painted into a RECT (not an ellipse): the gradient makes
    # the circle, and a rect has no curved edge to anti-alias, which kills the
    # dark fringe artifact.
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


def draw_ripple(painter: QPainter, pos: tuple, progress: float, color: QColor):
    """Expanding shockwave on click. progress: 0..1."""
    if not pos or progress >= 1.0:
        return

    mr, mg, mb = color.red(), color.green(), color.blue()
    px, py = pos
    center = QPointF(px, py)

    ease = 1.0 - (1.0 - progress) ** 3
    radius = 5.0 + ease * RIPPLE_MAX_RADIUS
    fade = 1.0 - progress

    # Layer 1: outer soft bloom
    bloom_r = radius * 1.6
    bloom_alpha = int(40 * fade ** 2)
    if bloom_alpha > 1:
        grad_bloom = QRadialGradient(center, bloom_r)
        grad_bloom.setColorAt(0.0, QColor(mr, mg, mb, bloom_alpha))
        grad_bloom.setColorAt(0.5, QColor(mr, mg, mb, bloom_alpha // 2))
        grad_bloom.setColorAt(1.0, QColor(mr, mg, mb, 0))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(grad_bloom)
        painter.drawEllipse(center, bloom_r, bloom_r)

    # Layer 2: dense fill — the shockwave body
    fill_alpha = int(160 * fade ** 1.8)
    if fill_alpha > 2:
        grad = QRadialGradient(center, radius)
        grad.setColorAt(0.0, QColor(mr, mg, mb, fill_alpha))
        grad.setColorAt(0.4, QColor(mr, mg, mb, int(fill_alpha * 0.7)))
        grad.setColorAt(0.8, QColor(mr, mg, mb, int(fill_alpha * 0.3)))
        grad.setColorAt(1.0, QColor(mr, mg, mb, 0))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(grad)
        painter.drawEllipse(center, radius, radius)

    # Layer 3: bright ring at the expanding edge
    painter.setPen(QPen(QColor(mr, mg, mb, int(255 * fade ** 1.3)), 3.5 * fade + 1.0))
    painter.setBrush(Qt.BrushStyle.NoBrush)
    painter.drawEllipse(center, radius, radius)

    # Layer 4: hot core flash (fades fast)
    if progress < 0.4:
        core_fade = 1.0 - (progress / 0.4)
        core_alpha = int(200 * core_fade ** 2)
        core_r = 4.0 + ease * 8.0
        grad_core = QRadialGradient(center, core_r)
        grad_core.setColorAt(0.0, QColor(255, 255, 255, core_alpha))
        grad_core.setColorAt(0.5, QColor(mr, mg, mb, core_alpha))
        grad_core.setColorAt(1.0, QColor(mr, mg, mb, 0))
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(grad_core)
        painter.drawEllipse(center, core_r, core_r)
