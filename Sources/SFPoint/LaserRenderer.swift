import AppKit

/// Dibujo puro del laser. Sin estado, sin herramientas, sin formas.
/// Traduccion 1:1 de core/laser.py — cada constante y cada formula se
/// conservaron para que el resultado sea visualmente identico.
enum LaserRenderer {

    /// Tope de la estela: redondeado por defecto, `butt` para el look original.
    static let trailCap: CGLineCap =
        (ProcessInfo.processInfo.environment["SFPOINT_TRAIL_CAP"] == "butt") ? .butt : .round

    // MARK: - Laser (estela + punto con bloom)

    static func drawLaser(in ctx: CGContext, pos: CGPoint?, trail: [CGPoint], color: NSColor) {
        let (lr, lg, lb) = color.rgb
        let dotDiam = Config.dotRadius * 2.0
        let n = trail.count

        if n >= 2 {
            // Tope de la estela. `.butt` es lo que hacia la version Python
            // (FlatCap): cada segmento termina plano y, como el ancho crece
            // segmento a segmento, se ven escalones. `.round` los cose y la
            // estela se lee continua. Se cambia con SFPOINT_TRAIL_CAP=butt.
            ctx.setLineCap(LaserRenderer.trailCap)
            ctx.setLineJoin(.round)

            // Pasada 1: glow ancho y suave por debajo (el sangrado de neon)
            strokeTrail(ctx, trail, n) { t in
                (RGBA(lr, lg, lb, t * t * 30.0 / 255.0), t * dotDiam * 2.5)
            }
            // Pasada 2: capa media de glow
            strokeTrail(ctx, trail, n) { t in
                (RGBA(lr, lg, lb, t * t * 80.0 / 255.0), t * dotDiam * 1.1)
            }
            // Pasada 3: nucleo caliente — el color viaja hacia blanco calido
            strokeTrail(ctx, trail, n) { t in
                let r = lr + (1.0 - lr) * t * 0.6
                let g = lg + (240.0/255.0 - lg) * t * 0.4
                let b = lb + (180.0/255.0 - lb) * t * 0.3
                return (RGBA(r, g, b, t * t * 200.0 / 255.0), t * dotDiam * 0.6)
            }
        }

        guard let p = pos else { return }

        // El gradiente radial se pinta sobre un RECT, no sobre una elipse: el
        // gradiente YA forma el circulo, y un rectangulo no tiene borde curvo
        // que suavizar — asi se elimina el halo oscuro del anti-aliasing.
        let fullR    = Config.glowRadius * 2.5
        let dotStop  = Config.dotRadius / fullR
        let glowStop = Config.glowRadius / fullR
        let bloomStop = (Config.glowRadius * 2.0) / fullR

        let stops: [(CGFloat, CGColor)] = [
            (0.0,             RGBA(1.0, 250/255, 220/255, 1.0)),
            (dotStop * 0.4,   RGBA(1.0, 220/255, 140/255, 240/255)),
            (dotStop * 0.7,   RGBA(lr, lg, lb, 210/255)),
            (dotStop,         RGBA(lr, lg, lb, 160/255)),
            (glowStop * 0.6,  RGBA(lr, lg, lb,  60/255)),
            (glowStop,        RGBA(lr, lg, lb,  25/255)),
            (bloomStop * 0.7, RGBA(lr, lg, lb,  10/255)),
            (bloomStop,       RGBA(lr, lg, lb,   3/255)),
            (1.0,             RGBA(lr, lg, lb, 0.0)),
        ]
        drawRadial(ctx, center: p, radius: fullR, stops: stops)
    }

    private static func strokeTrail(_ ctx: CGContext, _ trail: [CGPoint], _ n: Int,
                                    _ style: (CGFloat) -> (CGColor, CGFloat)) {
        for i in 1..<n {
            let t = CGFloat(i + 1) / CGFloat(n)
            let (color, width) = style(t)
            guard width > 0 else { continue }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.beginPath()
            ctx.move(to: trail[i - 1])
            ctx.addLine(to: trail[i])
            ctx.strokePath()
        }
    }

    // MARK: - Ripple (onda de choque del clic)

    static func drawRipple(in ctx: CGContext, pos: CGPoint, progress: CGFloat, color: NSColor) {
        guard progress < 1.0 else { return }
        let (mr, mg, mb) = color.rgb

        let ease = 1.0 - pow(1.0 - progress, 3)
        let radius = 5.0 + ease * Config.rippleMaxRadius
        let fade = 1.0 - progress

        // Capa 1: bloom exterior
        let bloomR = radius * 1.6
        let bloomAlpha = 40.0 * pow(fade, 2) / 255.0
        if bloomAlpha > 1.0/255.0 {
            drawRadial(ctx, center: pos, radius: bloomR, stops: [
                (0.0, RGBA(mr, mg, mb, bloomAlpha)),
                (0.5, RGBA(mr, mg, mb, bloomAlpha / 2)),
                (1.0, RGBA(mr, mg, mb, 0.0)),
            ])
        }

        // Capa 2: relleno denso — el cuerpo de la onda
        let fillAlpha = 160.0 * pow(fade, 1.8) / 255.0
        if fillAlpha > 2.0/255.0 {
            drawRadial(ctx, center: pos, radius: radius, stops: [
                (0.0, RGBA(mr, mg, mb, fillAlpha)),
                (0.4, RGBA(mr, mg, mb, fillAlpha * 0.7)),
                (0.8, RGBA(mr, mg, mb, fillAlpha * 0.3)),
                (1.0, RGBA(mr, mg, mb, 0.0)),
            ])
        }

        // Capa 3: anillo brillante en el borde que se expande
        ctx.setStrokeColor(RGBA(mr, mg, mb, 255.0 * pow(fade, 1.3) / 255.0))
        ctx.setLineWidth(3.5 * fade + 1.0)
        ctx.strokeEllipse(in: CGRect(x: pos.x - radius, y: pos.y - radius,
                                     width: radius * 2, height: radius * 2))

        // Capa 4: destello del nucleo (se apaga rapido)
        if progress < 0.4 {
            let coreFade = 1.0 - (progress / 0.4)
            let coreAlpha = 200.0 * pow(coreFade, 2) / 255.0
            let coreR = 4.0 + ease * 8.0
            drawRadial(ctx, center: pos, radius: coreR, stops: [
                (0.0, RGBA(1, 1, 1, coreAlpha)),
                (0.5, RGBA(mr, mg, mb, coreAlpha)),
                (1.0, RGBA(mr, mg, mb, 0.0)),
            ])
        }
    }

    // MARK: - Helpers

    private static func drawRadial(_ ctx: CGContext, center: CGPoint, radius: CGFloat,
                                   stops: [(CGFloat, CGColor)]) {
        guard radius > 0 else { return }
        let colors = stops.map { $0.1 } as CFArray
        var locations = stops.map { $0.0 }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: &locations) else { return }
        ctx.saveGState()
        ctx.drawRadialGradient(gradient,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius,
                               options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }
}

@inline(__always)
func RGBA(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
    CGColor(srgbRed: max(0, min(1, r)), green: max(0, min(1, g)),
            blue: max(0, min(1, b)), alpha: max(0, min(1, a)))
}
