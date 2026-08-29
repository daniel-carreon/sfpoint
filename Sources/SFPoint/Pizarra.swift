import AppKit
import Darwin

/**
 * LA PIZARRA — el modelo. Trazos, instrumentos y la regla de la goma.
 *
 * Sin AppKit de por medio salvo `NSColor`: aquí no se pinta ni se escuchan
 * eventos, se guarda QUÉ hay dibujado. La pantalla es de `PizarraOverlay` y la
 * mano, de `PizarraController`.
 *
 * Todo vive en COORDENADAS GLOBALES de escritorio (las de `NSEvent.mouseLocation`,
 * con la Y hacia arriba). Es la misma decisión que ya tomó el láser: un trazo
 * que cruza de un monitor a otro no se parte, porque nadie lo guarda "dentro"
 * de una pantalla — cada overlay traslada por su origen y pinta la parte que le toca.
 */

// ════════════════════════════════════════════════════════════════════════════
// MARK: instrumentos
// ════════════════════════════════════════════════════════════════════════════

enum Instrumento: Int, CaseIterable {
    case lapiz, marcador, goma

    var nombre: String {
        switch self {
        case .lapiz:    return "Lápiz"
        case .marcador: return "Marcador"
        case .goma:     return "Goma"
        }
    }

    /// La escalera de grosores de CADA instrumento. Son dos escaleras distintas
    /// a propósito: una goma fina no es una goma, es un lápiz que quita.
    var escalera: [Double] {
        switch self {
        case .lapiz:    return [1, 2, 3, 4, 6, 9, 13, 18, 26]
        case .marcador: return [8, 12, 18, 26, 38, 54]
        case .goma:     return [8, 16, 28, 48, 80]
        }
    }

    var grosorPorDefecto: Double {
        switch self {
        case .lapiz:    return 6      // sobre un monitor de 27" un 4 se pierde
        case .marcador: return 26
        case .goma:     return 28
        }
    }
}

/**
 * LOS DOS MODOS DE LA GOMA.
 *
 * No son un ajuste: son dos gestos distintos que la mano ya conoce de otras
 * apps, y ninguno sustituye al otro.
 *
 *  · `parcial` — la goma de verdad: se lleva SOLO el pedazo de trazo por el que
 *    pasas y deja el resto. Es lo que quieres para abrir un hueco en una llave,
 *    limpiar el rabo de una letra o corregir medio subrayado.
 *  · `trazo` — el borrador de componentes: roza un trazo y se va ENTERO. Es lo
 *    que quieres cuando el garabato sobra completo y no quieres perseguirlo.
 *
 * El corte es GEOMÉTRICO, no de píxeles: el trazo se parte en los pedazos que
 * quedan fuera del disco, cada uno con su presión y su inclinación intactas. Un
 * borrado de píxeles obligaría a rasterizar la pizarra y con eso se irían el
 * deshacer, el motor de tinta y la garantía de que el trazo vivo y el guardado
 * son el mismo dibujo.
 */
enum ModoGoma: Int, CaseIterable {
    case parcial, trazo

    var nombre: String { self == .parcial ? "Goma" : "Trazo entero" }
    var ayuda: String {
        self == .parcial ? "Borra solo por donde pasas" : "Roza un trazo y se va entero"
    }
    var simbolo: String { self == .parcial ? "eraser" : "eraser.line.dashed" }
    var otro: ModoGoma { self == .parcial ? .trazo : .parcial }
}

/// La paleta. Cinco y no más: sobre una pantalla ajena hacen falta los dos
/// colores de marca, blanco y negro (según lo que haya debajo) y un rojo para
/// señalar. Un selector de color entero sería el panel de ajustes que el
/// CLAUDE.md de esta app prohíbe.
enum TintaColor: Int, CaseIterable {
    case morado, ambar, blanco, negro, rojo

    var color: NSColor {
        switch self {
        case .morado: return Config.morado
        case .ambar:  return Config.ambar
        case .blanco: return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .negro:  return NSColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        case .rojo:   return NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)
        }
    }

    var nombre: String {
        switch self {
        case .morado: return "Morado"
        case .ambar:  return "Ámbar"
        case .blanco: return "Blanco"
        case .negro:  return "Negro"
        case .rojo:   return "Rojo"
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: el trazo
// ════════════════════════════════════════════════════════════════════════════

/**
 * Un trazo terminado. Es una CLASE y no una estructura por dos razones que se
 * pagan solas: el contorno se calcula UNA vez y se guarda aquí (el motor es
 * caro comparado con rellenar un camino ya hecho), y la pila de deshacer puede
 * guardar fotos del arreglo de trazos sin duplicar un solo punto.
 *
 * Un trazo no se modifica nunca después de terminado: se agrega o se quita.
 * Por eso compartir la referencia entre la pizarra y su historia es seguro.
 */
final class Trazo {
    let puntos: [PuntoTinta]
    let color: NSColor
    /// El marcador es translúcido: subraya sin tapar lo que hay debajo.
    let alpha: Double
    let grosor: Double
    let marcador: Bool

    private var caminoCache: CGPath?
    private var cajaCache: CGRect?

    init(puntos: [PuntoTinta], color: NSColor, grosor: Double, marcador: Bool) {
        self.puntos = puntos
        self.color = color
        self.grosor = grosor
        self.marcador = marcador
        self.alpha = marcador ? 0.30 : 1.0
    }

    var opciones: Tinta.Opciones { Tinta.Opciones(grosor: grosor, marcador: marcador) }

    /// El contorno relleno, en coordenadas globales.
    var camino: CGPath? {
        if let c = caminoCache { return c }
        let c = Tinta.camino(puntos, opciones)
        caminoCache = c
        return c
    }

    /// La caja que ocupa, ya con el ensanche máximo de la presión. Se usa para
    /// no repintar pantallas que este trazo ni toca.
    var caja: CGRect {
        if let c = cajaCache { return c }
        guard let cam = camino else {
            cajaCache = .null
            return .null
        }
        let c = cam.boundingBoxOfPath.insetBy(dx: -2, dy: -2)
        cajaCache = c
        return c
    }

    /// Lo que la tinta se ENSANCHA por encima de su grosor nominal cuando la
    /// presión aprieta. La goma tiene que alcanzar lo mismo que el ojo ve, o
    /// pasarías por encima de tinta visible sin llevártela. (Igual que sfmap.)
    var medioAncho: Double {
        Tinta.diametro(opciones) * 0.5 * Tinta.ANCHO_MAX
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: la pizarra
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class Pizarra {

    private(set) var trazos: [Trazo] = []

    /// La historia son FOTOS del arreglo, no una lista de operaciones inversas.
    /// Es barato porque un `Trazo` es una referencia: una foto de 60 trazos son
    /// 60 punteros, no 60 copias de sus puntos. Y no hay forma de que una
    /// operación inversa mal escrita deje la pizarra en un estado imposible.
    private var atras: [[Trazo]] = []
    private var adelante: [[Trazo]] = []
    private let topeHistoria = 80

    var estaVacia: Bool { trazos.isEmpty }
    var puedeDeshacer: Bool { !atras.isEmpty }
    var puedeRehacer: Bool { !adelante.isEmpty }

    // MARK: mutaciones

    private func recordar() {
        atras.append(trazos)
        if atras.count > topeHistoria { atras.removeFirst() }
        adelante.removeAll()
    }

    func agregar(_ t: Trazo) {
        recordar()
        trazos.append(t)
    }

    /// Quita los trazos indicados. Devuelve `true` si se llevó alguno — el
    /// llamador lo usa para no meter un paso de deshacer vacío cuando la goma
    /// pasó por encima de nada.
    @discardableResult
    func quitar(_ ids: Set<ObjectIdentifier>) -> Bool {
        guard !ids.isEmpty else { return false }
        let antes = trazos.count
        trazos.removeAll { ids.contains(ObjectIdentifier($0)) }
        return trazos.count != antes
    }

    func limpiar() {
        guard !trazos.isEmpty else { return }
        recordar()
        trazos.removeAll()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el corte — la goma parcial
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Se lleva el PEDAZO de trazo que cae dentro del disco y conserva el resto.
     *
     * Cada trazo tocado se sustituye por los tramos que quedan fuera. El corte
     * se hace en el punto EXACTO donde la línea entra y sale del círculo
     * —interpolando posición, presión, inclinación y tiempo— y no en la muestra
     * más cercana: con muestras a 20 unidades de distancia, cortar por muestras
     * deja mordidas de dos dedos donde pasó una goma de uno.
     *
     * Los cabos que quedan pasan por el mismo motor de tinta, así que se afilan
     * y se rematan como cualquier otro trazo. Por eso un trazo cortado no se ve
     * "roto": se ve como dos trazos.
     */
    @discardableResult
    func cortar(centro: CGPoint, radio: Double) -> Bool {
        var cambio = false
        var salida: [Trazo] = []
        salida.reserveCapacity(trazos.count)

        for t in trazos {
            // Descarte barato: si el disco ni roza su caja, el trazo sigue igual.
            guard t.caja.insetBy(dx: -radio, dy: -radio).contains(centro) else {
                salida.append(t); continue
            }
            let pedazos = Pizarra.partir(t.puntos, centro: centro, radio: radio)
            if pedazos.count == 1 && pedazos[0].count == t.puntos.count {
                salida.append(t); continue      // no lo tocó de verdad
            }
            cambio = true
            for trozo in pedazos where trozo.count >= 1 {
                salida.append(Trazo(puntos: trozo, color: t.color,
                                    grosor: t.grosor, marcador: t.marcador))
            }
        }
        if cambio { trazos = salida }
        return cambio
    }

    /// Los tramos de la polilínea que quedan FUERA del círculo, cortados en el
    /// cruce exacto. Es puro para poder probarlo sin pantalla.
    static func partir(_ pts: [PuntoTinta], centro: CGPoint, radio: Double) -> [[PuntoTinta]] {
        func dentro(_ q: PuntoTinta) -> Bool {
            hypot(q.x - centro.x, q.y - centro.y) <= radio
        }
        guard pts.count > 1 else { return dentro(pts[0]) ? [] : [pts] }

        var out: [[PuntoTinta]] = []
        var actual: [PuntoTinta] = []

        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let da = dentro(a), db = dentro(b)

            if !da && actual.isEmpty { actual.append(a) }

            if da == db {
                if !da { actual.append(b) }          // los dos fuera: sigue el tramo
                else if !actual.isEmpty { out.append(actual); actual = [] }
                // ⚠️ los dos DENTRO puede aún cruzar el borde? No: el disco es
                // convexo, así que si los extremos están dentro, todo el
                // segmento lo está.
                continue
            }

            // Cruza el borde: se busca dónde, y se corta ahí.
            let ts = cruces(a, b, centro: centro, radio: radio)
            if da {
                // Sale del disco: el tramo nuevo empieza en el cruce de SALIDA.
                if let t = ts.last {
                    actual = [interpolar(a, b, t), b]
                } else {
                    actual = [b]
                }
            } else {
                // Entra al disco: el tramo se cierra en el cruce de ENTRADA.
                if let t = ts.first { actual.append(interpolar(a, b, t)) }
                if actual.count >= 1 { out.append(actual) }
                actual = []
            }
        }
        if !dentro(pts[pts.count - 1]) || !actual.isEmpty {
            if actual.isEmpty { actual = [pts[pts.count - 1]] }
            out.append(actual)
        }
        // Un cabo de un solo punto es una mota: se queda solo si de verdad era
        // un toque suelto, no si es la esquirla de un corte.
        return out.filter { $0.count >= 2 }
    }

    /// Los parámetros donde el segmento cruza la circunferencia, ordenados.
    private static func cruces(_ a: PuntoTinta, _ b: PuntoTinta,
                               centro: CGPoint, radio: Double) -> [Double] {
        let dx = b.x - a.x, dy = b.y - a.y
        let fx = a.x - centro.x, fy = a.y - centro.y
        let A = dx * dx + dy * dy
        guard A > 1e-12 else { return [] }
        let B = 2 * (fx * dx + fy * dy)
        let C = fx * fx + fy * fy - radio * radio
        let disc = B * B - 4 * A * C
        guard disc >= 0 else { return [] }
        let r = disc.squareRoot()
        return [(-B - r) / (2 * A), (-B + r) / (2 * A)]
            .filter { $0 >= 0 && $0 <= 1 }
            .sorted()
    }

    /// El punto intermedio con TODO interpolado: si solo se interpolara la
    /// posición, el cabo del corte nacería con la presión del vecino y se vería
    /// un escalón de grosor justo en el borde de la goma.
    private static func interpolar(_ a: PuntoTinta, _ b: PuntoTinta, _ t: Double) -> PuntoTinta {
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var q = PuntoTinta(x: m(a.x, b.x), y: m(a.y, b.y), p: m(a.p, b.p))
        q.ix = m(a.ix, b.ix)
        q.iy = m(a.iy, b.iy)
        q.t = (a.t >= 0 && b.t >= 0) ? m(a.t, b.t) : -1
        return q
    }

    /// Abre un paso de deshacer que se cerrará con varios cambios dentro (el
    /// arrastre de la goma se lleva N trazos y se deshace de una vez, como una
    /// sola pasada de la mano).
    func abrirPaso() { recordar() }

    /// Cierra el paso abierto SIN dejar huella, cuando resultó que no cambió
    /// nada. Un deshacer que no deshace nada es peor que no tenerlo.
    func cancelarPaso() {
        if let ultima = atras.last, ultima.count == trazos.count {
            atras.removeLast()
        }
    }

    func deshacer() {
        guard let previo = atras.popLast() else { return }
        adelante.append(trazos)
        trazos = previo
    }

    func rehacer() {
        guard let siguiente = adelante.popLast() else { return }
        atras.append(trazos)
        trazos = siguiente
    }

    // MARK: la regla de la goma

    /**
     * QUÉ ALCANZA EL DISCO. Portado de `sfmap/Goma.swift`, con su decisión
     * central intacta: **el disco es la verdad** — el radio que se pinta es el
     * radio que borra. Una goma que promete un área y actúa en otra obliga a
     * la mano a apuntar en vez de a pasar, que es justo lo que una goma no debe
     * pedir.
     *
     * Aquí solo hay tinta (no hay cajas ni texto que proteger), así que el
     * "alcance" de sfmap no hace falta: la goma se lleva trazos y punto.
     */
    func alcanzados(centro: CGPoint, radio: Double) -> Set<ObjectIdentifier> {
        var out = Set<ObjectIdentifier>()
        for t in trazos {
            let alcance = radio + t.medioAncho
            // Descarte barato por caja antes de mirar segmento a segmento.
            guard t.caja.insetBy(dx: -alcance, dy: -alcance).contains(centro) else { continue }
            if Pizarra.tocaTrazo(t, centro: centro, alcance: alcance) {
                out.insert(ObjectIdentifier(t))
            }
        }
        return out
    }

    private static func tocaTrazo(_ t: Trazo, centro: CGPoint, alcance: Double) -> Bool {
        let pts = t.puntos
        guard pts.count > 1 else {
            // Un toque de pluma es un punto suelto, y también se borra.
            guard let q = pts.first else { return false }
            return hypot(centro.x - q.x, centro.y - q.y) <= alcance
        }
        for i in 0..<(pts.count - 1) {
            let a = CGPoint(x: pts[i].x, y: pts[i].y)
            let b = CGPoint(x: pts[i + 1].x, y: pts[i + 1].y)
            if Pizarra.distanciaASegmento(centro, a, b) <= alcance { return true }
        }
        return false
    }

    static func distanciaASegmento(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let vx = b.x - a.x, vy = b.y - a.y
        let l2 = vx * vx + vy * vy
        guard l2 > 1e-12 else { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * vx + (p.y - a.y) * vy) / l2
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * vx), p.y - (a.y + t * vy))
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: el dial de la tableta
// ════════════════════════════════════════════════════════════════════════════

extension Pizarra {
    /**
     * ¿Este scroll lo manda el DIAL de la Kamvas o una rueda de verdad?
     *
     * Portado tal cual de `sfmap/Lienzo.swift`, medido allá con una sonda sobre
     * los aparatos de este escritorio: la rueda de un ratón entra por el HID del
     * sistema con **pid 0**, y el dial de la tableta llega como un evento
     * SINTÉTICO posteado por el proceso del driver de Huion. Ése es el único
     * rasgo fiable que los separa — `hasPreciseScrollingDeltas` NO sirve, mete
     * al ratón entero en la misma bolsa.
     *
     * Aquí solo lo usa la sonda (`SFPOINT_SONDA_DIAL`), porque sobre un lienzo a
     * pantalla completa toda rueda es calibre. Existe para poder PREGUNTARLE al
     * aparato en vez de adivinar el día que haga falta distinguirlos.
     *
     * Se cachea por pid: resolver el proceso en cada evento sería consultar al
     * sistema cien veces por giro.
     */
    private static var procesoDeTableta: [pid_t: Bool] = [:]

    static func esDialDeTableta(_ e: NSEvent) -> Bool {
        guard let crudo = e.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID),
              crudo > 0 else { return false }          // pid 0 = aparato real
        let pid = pid_t(crudo)
        if let ya = procesoDeTableta[pid] { return ya }
        var quien = ""
        if let app = NSRunningApplication(processIdentifier: pid) {
            quien = ((app.bundleIdentifier ?? "") + " " + (app.localizedName ?? "")).lowercased()
        }
        if quien.isEmpty {   // procesos sin cara: el driver puede no ser una app
            var buf = [CChar](repeating: 0, count: 256)
            if proc_name(pid, &buf, UInt32(buf.count)) > 0 {
                quien = String(cString: buf).lowercased()
            }
        }
        let esTableta = quien.contains("huion") || quien.contains("tablet")
        procesoDeTableta[pid] = esTableta
        return esTableta
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: el rasterizador — uno solo
// ════════════════════════════════════════════════════════════════════════════

/**
 * Pintar un contorno de tinta. Vive aquí, y no dentro de la vista, por la regla
 * que hizo válido el banco de sfmap: **el rasterizador es uno solo**. Si la
 * pantalla pintara por un lado y el banco de verificación por otro, el banco
 * mediría su propio dibujante y no el motor.
 */
enum PintorTinta {
    static func pintar(_ cam: CGPath, color: NSColor, alpha: Double, en ctx: CGContext) {
        let (r, g, b) = color.rgb
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: CGFloat(alpha)))
        ctx.addPath(cam)
        // NON-ZERO: un trazo que se cruza a sí mismo se rellena UNA vez, como
        // la tinta. Con `evenOdd` el cruce saldría hueco.
        ctx.fillPath(using: .winding)
    }
}
