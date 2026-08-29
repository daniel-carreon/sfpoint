import AppKit

/// La estela como CONTORNO RELLENO, no como N segmentos trazados.
///
/// ## Por que existe este archivo
///
/// La estela son 18 muestras del cursor, una por frame, con el ancho creciendo
/// hacia la cabeza. La version original (Python/Qt, y su traduccion 1:1 a Swift)
/// la pintaba trazando **un segmento a la vez** con `setLineWidth` distinto en
/// cada uno. Eso deja JUNTAS, y una junta con alpha parcial siempre se ve:
///
/// - con tope plano (`.butt`, el original) cada segmento termina en un borde
///   suavizado por su cuenta: la estela se lee como una ESCALERA de peldaños;
/// - con tope redondo (`.round`, lo que quedo por default en v3) los topes se
///   SOLAPAN y el alpha se compone dos veces en cada solape: la estela se lee
///   como un COLLAR DE CUENTAS, una perla por frame. Medido en el banco:
///   +19% de luminancia media contra el original, que es exactamente el alpha
///   que se esta pintando dos veces.
///
/// Las dos son el mismo defecto: **hay juntas porque hay segmentos.**
///
/// Aqui no hay segmentos. Se construye el contorno de la estela (una sola curva
/// cerrada, el centro desplazado ±ancho/2 sobre su normal), se recorta a el, y
/// el desvanecido se pinta con UN gradiente a lo largo del recorrido. Una sola
/// pasada de pintura por capa ⇒ cero juntas que componer.
///
/// Es la misma leccion que el motor de tinta de sfmap: un trazo de ancho
/// variable es un POLIGONO, no una pila de lineas.
enum TrailContour {

    /// Geometria que NO depende de la capa: se calcula una vez y las tres
    /// pasadas (glow ancho, glow medio, nucleo) la reutilizan.
    struct Prepared {
        let center: [CGPoint]      // centro remuestreado y suavizado
        let normals: [CGPoint]     // normal unitaria en cada muestra
        let stops: [CGFloat]       // posicion de cada muestra sobre la cuerda (0..1, creciente)
        let head: CGPoint
        let axis: (start: CGPoint, end: CGPoint)
    }

    /// Distancia objetivo entre muestras del centro remuestreado, en puntos.
    /// Mas fino no se nota (el ancho minimo de la capa mas delgada es ~4 px) y
    /// solo cuesta CPU en un lazo que corre a 60 fps.
    private static let sampleSpacing: CGFloat = 6

    // MARK: - Preparacion

    static func prepare(_ trail: [CGPoint]) -> Prepared? {
        guard trail.count >= 2 else { return nil }

        // Catmull-Rom por tramo, subdividiendo segun la LONGITUD del tramo: un
        // laser lento no paga puntos que no necesita, uno rapido no facetea.
        var center: [CGPoint] = []
        center.reserveCapacity(trail.count * 4)
        for i in 0..<(trail.count - 1) {
            let p0 = trail[max(i - 1, 0)]
            let p1 = trail[i]
            let p2 = trail[i + 1]
            let p3 = trail[min(i + 2, trail.count - 1)]
            let len = hypot(p2.x - p1.x, p2.y - p1.y)
            let sub = max(1, min(8, Int(ceil(len / sampleSpacing))))
            for k in 0..<sub {
                center.append(catmullRom(p0, p1, p2, p3, CGFloat(k) / CGFloat(sub)))
            }
        }
        center.append(trail[trail.count - 1])
        let m = center.count
        guard m >= 2 else { return nil }

        var normals = [CGPoint](repeating: .zero, count: m)
        for i in 0..<m {
            let a = center[max(i - 1, 0)], b = center[min(i + 1, m - 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 0.0001)
            normals[i] = CGPoint(x: -dy / len, y: dx / len)
        }

        // Paradas del gradiente: cada muestra proyectada sobre la cuerda
        // inicio→cabeza. Se fuerza el orden creciente para que una estela que
        // se curva sobre si misma no invierta el desvanecido (CGGradient exige
        // locations monotonas; si no, el degradado se rompe).
        let a = center[0], b = center[m - 1]
        let ax = b.x - a.x, ay = b.y - a.y
        let chord = hypot(ax, ay)
        var stops = [CGFloat](repeating: 0, count: m)
        if chord > 0.001 {
            var last: CGFloat = 0
            for i in 0..<m {
                var u = ((center[i].x - a.x) * ax + (center[i].y - a.y) * ay) / (chord * chord)
                u = min(max(u, 0), 1)
                if u <= last { u = min(last + 0.0005, 1) }
                last = u
                stops[i] = u
            }
        } else {
            for i in 0..<m { stops[i] = CGFloat(i) / CGFloat(m - 1) }
        }

        return Prepared(center: center, normals: normals, stops: stops,
                        head: b, axis: (a, b))
    }

    // MARK: - Una capa

    /// Rellena UNA capa de la estela. `width` y `color` reciben t ∈ 0…1
    /// (0 = cola, 1 = cabeza) — las mismas formulas que usaba el trazo.
    static func fill(_ ctx: CGContext, _ prep: Prepared,
                     width: (CGFloat) -> CGFloat,
                     color: (CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat)) {
        let m = prep.center.count
        let path = CGMutablePath()

        var left = [CGPoint](repeating: .zero, count: m)
        var right = [CGPoint](repeating: .zero, count: m)
        for i in 0..<m {
            let t = CGFloat(i) / CGFloat(m - 1)
            let h = max(width(t), 0.01) / 2
            let n = prep.normals[i]
            left[i]  = CGPoint(x: prep.center[i].x + n.x * h, y: prep.center[i].y + n.y * h)
            right[i] = CGPoint(x: prep.center[i].x - n.x * h, y: prep.center[i].y - n.y * h)
        }

        addSmooth(path, left, startNew: true)
        // Punta redonda en la cabeza: ahi es donde vive el punto laser y el
        // corte recto se nota justo debajo del brillo.
        let headHalf = max(width(1), 0.01) / 2
        path.addArc(center: prep.head, radius: headHalf,
                    startAngle: atan2(left[m-1].y - prep.head.y, left[m-1].x - prep.head.x),
                    endAngle:   atan2(right[m-1].y - prep.head.y, right[m-1].x - prep.head.x),
                    clockwise: true)
        addSmooth(path, right.reversed(), startNew: false)
        path.closeSubpath()

        var locations = prep.stops
        var colors: [CGColor] = []
        colors.reserveCapacity(m)
        for i in 0..<m {
            let t = CGFloat(i) / CGFloat(m - 1)
            let (r, g, b, a) = color(t)
            colors.append(RGBA(r, g, b, a))
        }
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colors as CFArray, locations: &locations)
        else { return }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(grad, start: prep.axis.start, end: prep.axis.end,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // MARK: - Helpers

    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint,
                                   _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t, t3 = t2 * t
        @inline(__always) func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * ((2 * b) + (-a + cc) * t
                   + (2 * a - 5 * b + 4 * cc - d) * t2
                   + (-a + 3 * b - 3 * cc + d) * t3)
        }
        return CGPoint(x: c(p0.x, p1.x, p2.x, p3.x), y: c(p0.y, p1.y, p2.y, p3.y))
    }

    /// Une los puntos con cuadraticas de punto medio: el contorno no muestra
    /// los vertices del remuestreo.
    private static func addSmooth(_ path: CGMutablePath, _ pts: [CGPoint], startNew: Bool) {
        guard pts.count >= 2 else { return }
        if startNew { path.move(to: pts[0]) } else { path.addLine(to: pts[0]) }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                              y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
    }
}
