import AppKit

/**
 * LA PALETA — el espejo de la mano.
 *
 * ⚠️ El `CLAUDE.md` de esta app prohíbe barras y paneles, y con razón: la v1
 * tenía una barra de herramientas flotante y un panel de ajustes que nadie usó.
 * Esto NO es aquello, y la diferencia importa:
 *
 *  · Un panel de AJUSTES guarda preferencias que se tocan una vez al año.
 *  · Una paleta de DIBUJO dice qué instrumento tienes en la mano AHORA. Sin
 *    ella, los atajos de una letra son fe ciega: Daniel entró al modo y no
 *    supo si estaba en lápiz o en goma, ni de qué color, ni de qué calibre.
 *    *"no veo el panel de lapiz goma etc... ni colores ni grosor ni nada"*.
 *
 * Es un ESPEJO además de una cabina: se opera igual con el teclado, y lo que
 * cambies por teclado se ve aquí al instante. Nunca es la única vía.
 *
 * Vive en su PROPIO panel, por encima del lienzo. Eso es lo que hace que
 * pulsar un botón no deje un garabato: el clic entra por una ventana distinta
 * y nunca toca la vista que dibuja.
 */
@MainActor
final class PaletaPizarra {

    private var panel: NSPanel?
    private let vista = PaletaVista()
    let tira = TiraGrosores()
    private static let clavePos = "sfpoint.paleta.origen"

    weak var ctrl: PizarraController? {
        didSet { vista.ctrl = ctrl; tira.ctrl = ctrl }
    }

    /// Alto y ancho salen del contenido: si cambian los botones, cambia la caja.
    private var tamano: NSSize { vista.tamanoNatural }

    private func construir() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: tamano),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false   // la arrastra la vista, por el asa
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        // Por encima del lienzo (que ya va en floating+2). El nivel SIEMPRE
        // después de `isFloatingPanel`, que lo reescribe.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        vista.frame = NSRect(origin: .zero, size: tamano)
        vista.paleta = self
        tira.paleta = self
        p.contentView = vista
        p.acceptsMouseMovedEvents = true    // sin esto los rótulos no aparecen
        vista.recolocarRotulos()
        return p
    }

    func mostrar(en pantalla: NSScreen?) {
        let p = panel ?? construir()
        panel = p
        p.setContentSize(tamano)
        p.setFrameOrigin(origenGuardado(pantalla: pantalla, tamano: tamano))
        vista.needsDisplay = true
        p.orderFrontRegardless()
    }

    func ocultar() { tira.cerrar(); panel?.orderOut(nil) }

    func refrescar() { vista.needsDisplay = true; tira.refrescar() }

    /// La tira se cierra sola en cuanto la mano vuelve al lienzo: es un gesto,
    /// no una ventana que se queda estorbando encima de lo que vas a anotar.
    func cerrarTira() { tira.cerrar() }

    var estaVisible: Bool { panel?.isVisible ?? false }

    func alternarVisible(en pantalla: NSScreen?) {
        if estaVisible { ocultar() } else { mostrar(en: pantalla) }
    }

    /// Mover la paleta con la tira abierta la dejaría flotando en el aire.
    func seguirConLaTira() {
        guard tira.estaAbierta else { return }
        tira.abrir(ancla: vista.anclaGrosor)
    }

    // MARK: sitio

    /// Donde la dejó la última vez. Si esa posición ya no cae en ninguna
    /// pantalla (desconectaste el monitor), vuelve al centro-abajo en vez de
    /// quedarse invisible en un escritorio que ya no existe.
    private func origenGuardado(pantalla: NSScreen?, tamano: NSSize) -> NSPoint {
        let d = UserDefaults.standard
        if let s = d.string(forKey: Self.clavePos) {
            let p = NSPointFromString(s)
            let caja = NSRect(origin: p, size: tamano)
            if NSScreen.screens.contains(where: { $0.frame.intersects(caja.insetBy(dx: 20, dy: 10)) }) {
                return p
            }
        }
        let f = (pantalla ?? NSScreen.main)?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: f.midX - tamano.width / 2, y: f.minY + 64)
    }

    func recordarPosicion() {
        guard let p = panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: Self.clavePos)
    }

    func mover(_ delta: NSSize) {
        guard let p = panel else { return }
        p.setFrameOrigin(NSPoint(x: p.frame.origin.x + delta.width,
                                 y: p.frame.origin.y + delta.height))
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: la vista
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class PaletaVista: NSView, NSViewToolTipOwner {

    weak var ctrl: PizarraController?
    weak var paleta: PaletaPizarra?

    /// Qué hace cada zona clicable. La lista es el ÚNICO sitio donde vive la
    /// geometría: dibujar y acertar el clic leen de aquí, así que no pueden
    /// desincronizarse — que es el defecto clásico de una barra hecha a mano.
    private enum Accion: Equatable {
        case asa
        case instrumento(Instrumento)
        case color(TintaColor)
        case grosor
        case deshacer, rehacer, limpiar, congelar, salir
    }
    private struct Zona { let r: CGRect; let a: Accion }

    private let alto: CGFloat = 52
    private let pad: CGFloat = 8
    private let botón: CGFloat = 36
    private let punto: CGFloat = 22
    private let asa: CGFloat = 16
    private let sep: CGFloat = 11

    var tamanoNatural: NSSize {
        NSSize(width: zonas(ancho: 2000).ancho, height: alto)
    }

    // MARK: geometría

    private func zonas(ancho: CGFloat) -> (lista: [Zona], ancho: CGFloat) {
        var z: [Zona] = []
        var x = pad
        let y = (alto - botón) / 2

        z.append(Zona(r: CGRect(x: 4, y: 0, width: asa, height: alto), a: .asa))
        x = asa + 6

        for i in Instrumento.allCases {
            z.append(Zona(r: CGRect(x: x, y: y, width: botón, height: botón), a: .instrumento(i)))
            x += botón + 2
        }
        x += sep

        let yp = (alto - punto) / 2
        for c in TintaColor.allCases {
            z.append(Zona(r: CGRect(x: x, y: yp, width: punto, height: punto), a: .color(c)))
            x += punto + 6
        }
        x += sep - 6

        // UN botón, no un `−/+`. La muestra que enseña es el calibre real que
        // vas a pintar; al pulsarlo se abre la escalera entera (ver TiraGrosores).
        z.append(Zona(r: CGRect(x: x, y: y, width: 48, height: botón), a: .grosor))
        x += 48 + sep

        for a in [Accion.deshacer, .rehacer, .limpiar, .congelar, .salir] {
            z.append(Zona(r: CGRect(x: x, y: y, width: botón, height: botón), a: a))
            x += botón + 2
        }
        x += pad - 2
        return (z, x)
    }

    private var muestraRect: CGRect {
        zonas(ancho: bounds.width).lista.first { $0.a == .grosor }?.r ?? .zero
    }

    /// La misma caja, pero en coordenadas de PANTALLA: la tira sale de aquí.
    var anclaGrosor: CGRect {
        guard let w = window else { return .zero }
        return w.convertToScreen(convert(muestraRect, to: nil))
    }

    /// El calibre PERSIGUE al nuevo en vez de saltar. Girando el dial rápido,
    /// una bola que parpadea no dice hacia dónde vas; una que crece, sí.
    let disco = Animador()

    // MARK: pintar

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let ctrl else { return }
        ctx.setShouldAntialias(true)

        // Fondo: grafito translúcido con borde de luz. Sobre una pantalla ajena
        // no se puede suponer qué hay debajo, así que la caja tiene que tener
        // cuerpo propio.
        let caja = bounds
        let redondo = CGPath(roundedRect: caja.insetBy(dx: 1, dy: 1),
                             cornerWidth: 13, cornerHeight: 13, transform: nil)
        ctx.addPath(redondo)
        ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 0.94))
        ctx.fillPath()
        ctx.addPath(redondo)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13))
        ctx.setLineWidth(1)
        ctx.strokePath()

        let z = zonas(ancho: caja.width).lista
        for zona in z {
            switch zona.a {
            case .asa:
                // Tres puntos: el gesto universal de "esto se arrastra".
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.25))
                for i in 0..<3 {
                    let cy = caja.midY - 7 + CGFloat(i) * 7
                    ctx.fillEllipse(in: CGRect(x: zona.r.midX - 1.5, y: cy - 1.5, width: 3, height: 3))
                }

            case .instrumento(let i):
                let activo = ctrl.instrumentoEfectivo == i
                pintarBoton(zona.r, activo: activo, en: ctx)
                icono(simbolo(i), zona.r, activo ? .white : NSColor(white: 0.72, alpha: 1), ctx)

            case .color(let c):
                let activo = ctrl.color == c && ctrl.instrumentoEfectivo != .goma
                let r = zona.r.insetBy(dx: activo ? 2 : 3.5, dy: activo ? 2 : 3.5)
                ctx.setFillColor(c.color.cgColor)
                ctx.fillEllipse(in: r)
                if c == .negro {   // sobre el grafito de la caja, el negro se pierde
                    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
                    ctx.setLineWidth(1)
                    ctx.strokeEllipse(in: r)
                }
                if activo {
                    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
                    ctx.setLineWidth(1.6)
                    ctx.strokeEllipse(in: zona.r.insetBy(dx: 0.8, dy: 0.8))
                }


            case .deshacer:
                pintarBoton(zona.r, activo: false, en: ctx)
                icono("arrow.uturn.backward", zona.r,
                      NSColor(white: ctrl.pizarra.puedeDeshacer ? 0.78 : 0.34, alpha: 1), ctx)
            case .rehacer:
                pintarBoton(zona.r, activo: false, en: ctx)
                icono("arrow.uturn.forward", zona.r,
                      NSColor(white: ctrl.pizarra.puedeRehacer ? 0.78 : 0.34, alpha: 1), ctx)
            case .limpiar:
                pintarBoton(zona.r, activo: false, en: ctx)
                icono("trash", zona.r,
                      NSColor(white: ctrl.pizarra.estaVacia ? 0.34 : 0.78, alpha: 1), ctx)
            case .congelar:
                pintarBoton(zona.r, activo: ctrl.modo == .congelada, en: ctx)
                icono("snowflake", zona.r,
                      ctrl.modo == .congelada ? .white : NSColor(white: 0.72, alpha: 1), ctx)
            case .salir:
                pintarBoton(zona.r, activo: false, en: ctx)
                icono("xmark", zona.r, NSColor(white: 0.72, alpha: 1), ctx, tamano: 12)
            case .grosor:
                break   // se pinta abajo, con su muestra y su número
            }
        }

        // La MUESTRA del calibre: un disco del diámetro real que vas a pintar,
        // con el color activo, y el número debajo. Es la misma verdad que el
        // disco de la goma en el lienzo — se ve lo que va a salir. Y es un
        // BOTÓN: al pulsarlo se abre la escalera entera.
        let m = muestraRect
        let abierta = paleta?.tira.estaAbierta ?? false
        let fondoM = CGPath(roundedRect: m.insetBy(dx: 2, dy: 2), cornerWidth: 9,
                            cornerHeight: 9, transform: nil)
        ctx.addPath(fondoM)
        ctx.setFillColor(abierta
            ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16)
            : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06))
        ctx.fillPath()
        let inst = ctrl.instrumentoEfectivo
        let destino = min(26.0, Tinta.diametro(Tinta.Opciones(grosor: ctrl.grosorActual,
                                                              marcador: inst == .marcador)))
        // La primera vez se PLANTA, no se persigue: el disco tiene que nacer con
        // el calibre puesto. Perseguir desde cero convertía abrir la paleta en
        // una animación que nadie pidió (y en el render headless, donde no corre
        // el reloj, dejaba una mota en vez de la muestra).
        if disco.valor <= 0.01 { disco.plantar(destino) } else { disco.objetivo = destino }
        let d = max(2.0, disco.valor)
        let cInst: NSColor = inst == .goma ? NSColor(white: 0.85, alpha: 1) : ctrl.color.color
        let disco = CGRect(x: m.midX - d / 2, y: m.midY - d / 2 + 4, width: d, height: d)
        if inst == .marcador {
            // El papel de debajo, para que la translucidez se vea como lo que es.
            ctx.setFillColor(CGColor(srgbRed: 0.88, green: 0.88, blue: 0.9, alpha: 1))
            ctx.fillEllipse(in: disco.insetBy(dx: -1.5, dy: -1.5))
        }
        ctx.setFillColor(cInst.withAlphaComponent(inst == .marcador ? 0.45 : 1).cgColor)
        ctx.fillEllipse(in: disco)
        if inst == .goma {
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5))
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: disco)
        }
        texto("\(Int(ctrl.grosorActual))", en: CGRect(x: m.minX, y: 4, width: m.width, height: 11),
              tamano: 9, color: NSColor(white: abierta ? 0.85 : 0.55, alpha: 1))
    }

    private func pintarBoton(_ r: CGRect, activo: Bool, en ctx: CGContext) {
        guard activo else { return }
        let p = CGPath(roundedRect: r.insetBy(dx: 2, dy: 2), cornerWidth: 9, cornerHeight: 9,
                       transform: nil)
        ctx.addPath(p)
        let (rr, gg, bb) = Config.morado.rgb
        ctx.setFillColor(CGColor(srgbRed: rr, green: gg, blue: bb, alpha: 0.92))
        ctx.fillPath()
    }

    private func simbolo(_ i: Instrumento) -> String {
        switch i {
        case .lapiz:    return "pencil"
        case .marcador: return "highlighter"
        case .goma:     return "eraser"
        }
    }

    private func icono(_ nombre: String, _ r: CGRect, _ color: NSColor, _ ctx: CGContext,
                       tamano: CGFloat = 15) {
        let cfg = NSImage.SymbolConfiguration(pointSize: tamano, weight: .medium)
        guard let img = NSImage(systemSymbolName: nombre, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) else { return }
        let s = img.size
        let destino = NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2,
                             width: s.width, height: s.height)
        NSGraphicsContext.saveGraphicsState()
        // Los símbolos son plantillas: se tiñen pintando el color ENCIMA con
        // `sourceAtop`, que es lo único que respeta su alfa.
        let tenido = NSImage(size: s)
        tenido.lockFocus()
        color.set()
        let todo = NSRect(origin: .zero, size: s)
        img.draw(in: todo)
        todo.fill(using: .sourceAtop)
        tenido.unlockFocus()
        tenido.draw(in: destino)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func texto(_ s: String, en r: CGRect, tamano: CGFloat, color: NSColor) {
        let at: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: tamano, weight: .semibold),
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: s, attributes: at)
        let w = str.size().width
        str.draw(at: NSPoint(x: r.midX - w / 2, y: r.minY))
    }

    // MARK: el clic

    private var arrastrando = false

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let zona = zonas(ancho: bounds.width).lista.first(where: { $0.r.contains(p) }) else {
            arrastrando = false
            return
        }
        guard let ctrl else { return }

        switch zona.a {
        case .asa:
            arrastrando = true
        case .instrumento(let i):
            ctrl.elegir(i)
        case .color(let c):
            ctrl.elegir(c)
        case .grosor:
            paleta?.tira.alternar(ancla: anclaGrosor)
        case .deshacer:
            ctrl.deshacer()
        case .rehacer:
            ctrl.rehacer()
        case .limpiar:
            ctrl.limpiar()
        case .congelar:
            ctrl.alternarCongelado()
        case .salir:
            ctrl.salir()
        }
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        guard arrastrando else { return }
        paleta?.mover(NSSize(width: e.deltaX, height: -e.deltaY))
        paleta?.seguirConLaTira()
    }

    override func mouseUp(with e: NSEvent) {
        if arrastrando { paleta?.recordarPosicion() }
        arrastrando = false
    }

    /// La rueda encima de la paleta también mueve el calibre: la mano ya está ahí.
    override func scrollWheel(with e: NSEvent) {
        guard abs(e.scrollingDeltaY) > 0.01 else { return }
        ctrl?.moverGrosor(pasos: e.scrollingDeltaY > 0 ? 1 : -1)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: los rótulos
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Daniel, viendo la paleta por primera vez: *"¿qué hace el copo de nieve?"*.
     * Un icono que hay que preguntar no comunica, y aquí ningún botón tiene
     * hueco para una palabra. Los rótulos nativos de macOS resuelven las dos
     * cosas: la barra sigue del mismo tamaño y cada botón dice su nombre Y SU
     * ATAJO, que es como se aprende a dejar de usar la barra.
     */
    private func rotulo(_ a: Accion) -> String {
        switch a {
        case .asa:                    return "Arrástrala para moverla · H la esconde"
        case .instrumento(.lapiz):    return "Lápiz  (P)"
        case .instrumento(.marcador): return "Marcador translúcido  (M)"
        case .instrumento(.goma):     return "Goma  (E)  ·  o voltea la pluma"
        case .color(let c):           return "\(c.nombre)  (\((TintaColor.allCases.firstIndex(of: c) ?? 0) + 1))"
        case .grosor:                 return "Grosor — clic para la escalera  ·  dial de la tableta, rueda, [ ]"
        case .deshacer:               return "Deshacer  (⌘Z)"
        case .rehacer:                return "Rehacer  (⇧⌘Z)"
        case .limpiar:                return "Limpiar la pizarra  (C)"
        case .congelar:               return "Congelar la tinta  (⌥⇧L)  ·  la deja fija y te devuelve el clic a las apps de abajo"
        case .salir:                  return "Salir y limpiar  (⌥L o Esc)"
        }
    }

    /// Se rehacen con la geometría, no una sola vez: si cambian los botones,
    /// cambian los rótulos, y no puede quedar uno apuntando al sitio de antes.
    func recolocarRotulos() {
        removeAllToolTips()
        for zona in zonas(ancho: bounds.width).lista {
            addToolTip(zona.r, owner: self, userData: nil)
        }
    }

    override func layout() {
        super.layout()
        recolocarRotulos()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // El calibre persigue al nuevo valor y repinta mientras dura el viaje.
        disco.alRepintar = { [weak self] in self?.needsDisplay = true }
        recolocarRotulos()
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let zona = zonas(ancho: bounds.width).lista.first(where: { $0.r.contains(point) })
        else { return "" }
        return rotulo(zona.a)
    }
}
