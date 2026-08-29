import AppKit

/**
 * LA TIRA DE GROSORES — un botón que se abre en la escalera entera.
 *
 * Daniel, 29 ago: *"no quiero el más o menos en el grosor; solo un botón que al
 * presionarlo muestra muchos grosores, como una barra horizontal para elegir
 * entre 9 niveles... lo mismo para goma, marcador y lápiz, pero cada uno con su
 * respectiva animación"*.
 *
 * El `−  ⬤  +` pedía CONTAR: para pasar de 1 a 9 había que pulsar ocho veces sin
 * ver a dónde ibas. La escalera entera se elige de un vistazo y un clic, y de
 * paso ENSEÑA cuántos peldaños hay — que con `−/+` era invisible.
 *
 * **Cada instrumento trae su escalera Y su marca:** el lápiz un disco lleno, el
 * marcador una banda translúcida, la goma un aro. Nueve niveles el lápiz, seis
 * el marcador, cinco la goma: son las mismas listas que mueve el dial de la
 * tableta, no una lista de adorno paralela.
 *
 * ⚠️ La marca de cada peldaño es RELATIVA a su escalera (el mayor llena la
 * casilla), no absoluta: la goma llega a 80 unidades y dibujarla a tamaño real
 * pediría una casilla de 80 px. Lo absoluto se ve donde importa —el disco de la
 * goma sobre el lienzo y la muestra del botón— y aquí lo que se compara es un
 * peldaño con el siguiente.
 */
@MainActor
final class TiraGrosores {

    private var panel: NSPanel?
    private let vista = TiraVista()
    weak var ctrl: PizarraController? { didSet { vista.ctrl = ctrl } }
    weak var paleta: PaletaPizarra? { didSet { vista.paleta = paleta } }

    var estaAbierta: Bool { panel?.isVisible ?? false }

    private func construir() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: vista.tamano),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.acceptsMouseMovedEvents = true
        // Por encima de la paleta (floating+3), que ya está por encima del lienzo.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 4)
        vista.tira = self
        p.contentView = vista
        return p
    }

    /// `ancla` es el botón de grosor en coordenadas de PANTALLA: la tira sale
    /// justo encima y centrada en él, no en un sitio fijo, porque la paleta se
    /// arrastra y una tira que no la sigue se lee como otra ventana.
    func abrir(ancla: CGRect) {
        let p = panel ?? construir()
        panel = p
        vista.frame = NSRect(origin: .zero, size: vista.tamano)
        p.setContentSize(vista.tamano)
        vista.recolocarRotulos()
        vista.needsDisplay = true

        let destino = sitio(ancla: ancla, tamano: vista.tamano)
        // Nace 8 px más abajo y transparente: el ascenso corto dice "esto sale
        // de ese botón" mejor que cualquier línea que los una.
        p.setFrame(NSRect(origin: CGPoint(x: destino.x, y: destino.y - 8), size: vista.tamano),
                   display: false)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(NSRect(origin: destino, size: vista.tamano), display: true)
            p.animator().alphaValue = 1
        }
    }

    func cerrar() {
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    func alternar(ancla: CGRect) { estaAbierta ? cerrar() : abrir(ancla: ancla) }

    func refrescar() {
        guard estaAbierta else { return }
        vista.needsDisplay = true
    }

    /// Encima del botón, y dentro de la pantalla: si la paleta está pegada a un
    /// borde, la tira se recoloca en vez de salirse.
    private func sitio(ancla: CGRect, tamano: NSSize) -> CGPoint {
        var x = ancla.midX - tamano.width / 2
        var y = ancla.maxY + 10
        let pantalla = NSScreen.screens.first { $0.frame.intersects(ancla) } ?? NSScreen.main
        if let f = pantalla?.visibleFrame {
            x = min(max(x, f.minX + 8), f.maxX - tamano.width - 8)
            if y + tamano.height > f.maxY { y = ancla.minY - tamano.height - 10 }
        }
        return CGPoint(x: x, y: y)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: la vista de la tira
// ════════════════════════════════════════════════════════════════════════════

@MainActor
final class TiraVista: NSView, NSViewToolTipOwner {

    weak var ctrl: PizarraController?
    weak var tira: TiraGrosores?
    weak var paleta: PaletaPizarra?

    private let casilla: CGFloat = 36
    private let pad: CGFloat = 9
    private let alto: CGFloat = 52
    private let sep: CGFloat = 12
    private var sobre: Int? = nil

    /**
     * La tira no es solo grosores: son LAS OPCIONES DEL INSTRUMENTO.
     *
     * Con la goma puesta, delante de la escalera aparecen sus dos modos —goma
     * parcial y trazo entero—. Es el patrón de Freeform y GoodNotes: la
     * herramienta activa, tocada otra vez, enseña lo suyo. Un panel aparte
     * "modo de goma" sería el ajuste que esta app no tiene.
     */
    private enum Celda: Equatable {
        case modo(ModoGoma)
        case grosor(Double)
    }

    private var celdas: [Celda] {
        var c: [Celda] = []
        if (ctrl?.instrumentoEfectivo ?? .lapiz) == .goma {
            c += ModoGoma.allCases.map { Celda.modo($0) }
        }
        c += escalera.map { Celda.grosor($0) }
        return c
    }

    private var hayModos: Bool { (ctrl?.instrumentoEfectivo ?? .lapiz) == .goma }

    /// La escalera pintada, con su selección animada. Ver `Animador`.
    private let deslizador = Animador()

    private var escalera: [Double] { (ctrl?.instrumentoEfectivo ?? .lapiz).escalera }

    var tamano: NSSize {
        NSSize(width: CGFloat(celdas.count) * casilla + pad * 2 + (hayModos ? sep : 0),
               height: alto)
    }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// El hueco extra separa los modos de la escalera: sin él, las dos filas de
    /// casillas se leen como una sola lista de siete cosas del mismo tipo.
    private func caja(_ i: Int) -> CGRect {
        let modos = hayModos ? ModoGoma.allCases.count : 0
        let extra: CGFloat = (hayModos && i >= modos) ? sep : 0
        return CGRect(x: pad + CGFloat(i) * casilla + extra, y: (alto - casilla) / 2,
                      width: casilla, height: casilla)
    }

    /// La casilla del grosor que está puesto ahora.
    private var indiceActual: Int {
        let g = ctrl?.grosorActual ?? 6
        let modos = hayModos ? ModoGoma.allCases.count : 0
        let i = escalera.enumerated()
            .min { abs($0.element - g) < abs($1.element - g) }?.offset ?? 0
        return modos + i
    }

    // MARK: pintar

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let ctrl else { return }
        ctx.setShouldAntialias(true)

        let fondo = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                           cornerWidth: 13, cornerHeight: 13, transform: nil)
        ctx.addPath(fondo)
        ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 0.96))
        ctx.fillPath()
        ctx.addPath(fondo)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13))
        ctx.setLineWidth(1)
        ctx.strokePath()

        let inst = ctrl.instrumentoEfectivo
        let lista = celdas

        // La pastilla del GROSOR se DESLIZA de una casilla a otra. Es la misma
        // idea que el aviso del dial en sfmap: interpolar convierte un dato en
        // un gesto, y de paso dice de dónde vienes. Va en píxeles y no en
        // índices porque entre los modos y la escalera hay un hueco.
        let destino = Double(caja(indiceActual).minX)
        if deslizador.valor <= 0.01 { deslizador.plantar(destino) }
        else { deslizador.objetivo = destino }
        pastilla(CGRect(x: CGFloat(deslizador.valor), y: (alto - casilla) / 2,
                        width: casilla, height: casilla), en: ctx)

        // La del MODO no se desliza: son dos casillas pegadas y un viaje de 36
        // px entre vecinas se lee como un parpadeo, no como un movimiento.
        if hayModos, let i = lista.firstIndex(of: .modo(ctrl.modoGoma)) {
            pastilla(caja(i), en: ctx)
        }

        let mayor = escalera.last ?? 1
        for (i, celda) in lista.enumerated() {
            let c = caja(i)
            let activo: Bool = switch celda {
                case .modo(let m): m == ctrl.modoGoma
                case .grosor: i == indiceActual
            }
            if sobre == i && !activo {
                let h = CGPath(roundedRect: c.insetBy(dx: 2, dy: 2), cornerWidth: 9,
                               cornerHeight: 9, transform: nil)
                ctx.addPath(h)
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
                ctx.fillPath()
            }
            switch celda {
            case .modo(let m):
                icono(m.simbolo, c, activo ? .white : NSColor(white: 0.72, alpha: 1), ctx)
            case .grosor(let g):
                marca(inst, g: g, mayor: mayor, en: c, ctx: ctx, activo: activo)
            }
        }
    }

    private func pastilla(_ r: CGRect, en ctx: CGContext) {
        let p = CGPath(roundedRect: r.insetBy(dx: 2, dy: 2), cornerWidth: 9,
                       cornerHeight: 9, transform: nil)
        ctx.addPath(p)
        let (rr, gg, bb) = Config.morado.rgb
        ctx.setFillColor(CGColor(srgbRed: rr, green: gg, blue: bb, alpha: 0.92))
        ctx.fillPath()
    }

    private func icono(_ nombre: String, _ r: CGRect, _ color: NSColor, _ ctx: CGContext) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        guard let img = NSImage(systemSymbolName: nombre, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) else { return }
        let s = img.size
        let tenido = NSImage(size: s)
        tenido.lockFocus()
        color.set()
        let todo = NSRect(origin: .zero, size: s)
        img.draw(in: todo)
        todo.fill(using: .sourceAtop)
        tenido.unlockFocus()
        tenido.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2,
                               width: s.width, height: s.height))
    }

    /// Cada instrumento se dibuja como lo que ES: el lápiz un disco lleno, el
    /// marcador una banda translúcida y la goma un aro. Un peldaño que se
    /// pinta igual en las tres herramientas no dice cuál estás calibrando.
    private func marca(_ inst: Instrumento, g: Double, mayor: Double, en c: CGRect,
                       ctx: CGContext, activo: Bool) {
        let color = inst == .goma ? NSColor(white: 0.92, alpha: 1) : (ctrl?.color.color ?? .white)
        let (r, gg, b) = color.rgb
        // RAÍZ, no lineal: con `g/mayor` los peldaños 1..4 del lápiz caen todos
        // por debajo de 4 px y la escalera se ve como cuatro motas iguales. La
        // raíz reparte el recorrido donde están los peldaños, que es abajo.
        let d = max(4.0, 24.0 * (g / mayor).squareRoot())

        switch inst {
        case .lapiz:
            ctx.setFillColor(CGColor(srgbRed: r, green: gg, blue: b, alpha: activo ? 1 : 0.92))
            ctx.fillEllipse(in: CGRect(x: c.midX - d / 2, y: c.midY - d / 2, width: d, height: d))
        case .marcador:
            let h = max(3.0, d)
            let banda = CGRect(x: c.midX - 11, y: c.midY - h / 2, width: 22, height: h)
            // El papel de debajo. Sin él, ámbar al 45% sobre grafito se lee
            // marrón: el peldaño mentiría sobre el color con el que pinta.
            ctx.setFillColor(CGColor(srgbRed: 0.88, green: 0.88, blue: 0.9, alpha: 1))
            ctx.fill(banda.insetBy(dx: -1.5, dy: -1.5))
            ctx.setFillColor(CGColor(srgbRed: r, green: gg, blue: b, alpha: 0.45))
            ctx.fill(banda)
        case .goma:
            ctx.setStrokeColor(CGColor(srgbRed: r, green: gg, blue: b, alpha: activo ? 1 : 0.85))
            ctx.setLineWidth(1.6)
            ctx.strokeEllipse(in: CGRect(x: c.midX - d / 2, y: c.midY - d / 2,
                                         width: d, height: d))
        }
    }

    // MARK: el clic

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let lista = celdas
        guard let i = lista.indices.first(where: { caja($0).contains(p) }) else { return }
        switch lista[i] {
        case .modo(let m):
            // Elegir modo NO cierra: casi siempre lo siguiente es calibrar la
            // goma que acabas de elegir, y cerrar obligaría a volver a abrir.
            ctrl?.ponerModoGoma(m)
            needsDisplay = true
        case .grosor(let g):
            ctrl?.ponerGrosor(g)
            needsDisplay = true
            tira?.cerrar()   // el calibre es el último paso: la tira es un gesto
        }
    }

    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let nuevo = celdas.indices.first { caja($0).contains(p) }
        if nuevo != sobre { sobre = nuevo; needsDisplay = true }
    }

    override func mouseExited(with e: NSEvent) {
        if sobre != nil { sobre = nil; needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
        deslizador.alRepintar = { [weak self] in self?.needsDisplay = true }
        deslizador.plantar(Double(caja(indiceActual).minX))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    func recolocarRotulos() {
        removeAllToolTips()
        for i in celdas.indices { addToolTip(caja(i), owner: self, userData: nil) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        let lista = celdas
        guard let i = lista.indices.first(where: { caja($0).contains(point) }) else { return "" }
        return switch lista[i] {
            case .modo(let m): "\(m.nombre) — \(m.ayuda)  (E alterna)"
            case .grosor(let g): "Grosor \(Int(g))"
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: el animador
// ════════════════════════════════════════════════════════════════════════════

/**
 * Un número que PERSIGUE a otro. Existe porque una selección que salta de una
 * casilla a otra dice el dato pero no el CAMBIO: girando el dial rápido, lo
 * único que se ve es una pastilla parpadeando. Es la misma lección del aviso
 * del dial en sfmap — *"me gustaría ver cómo cambia el grosor con una ligera
 * animación"*— y aquí sirve tanto para la pastilla de la tira como para la
 * muestra de calibre de la paleta.
 *
 * El temporizador SOLO vive mientras hay algo que mover: en cuanto llega, se
 * apaga. Una animación que sigue corriendo quieta es un 60 fps regalado.
 */
@MainActor
final class Animador {
    var objetivo: Double = 0 { didSet { if abs(objetivo - valor) > 0.001 { arrancar() } } }
    private(set) var valor: Double = 0
    var alRepintar: (() -> Void)?
    /// Cuánto se acerca por fotograma. 0.28 llega en ~6 cuadros: se ve el
    /// movimiento sin que la mano tenga que esperarlo.
    var paso: Double = 0.28
    private var reloj: Timer?

    func plantar(_ v: Double) {
        reloj?.invalidate(); reloj = nil
        valor = v
        objetivo = v
    }

    private func arrancar() {
        guard reloj == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.latir() }
        }
        RunLoop.main.add(t, forMode: .common)
        reloj = t
    }

    private func latir() {
        let d = objetivo - valor
        if abs(d) < 0.004 {
            valor = objetivo
            reloj?.invalidate(); reloj = nil
            alRepintar?()
            return
        }
        valor += d * paso
        alRepintar?()
    }
}
