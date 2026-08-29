import AppKit

/**
 * LA SUPERFICIE — un panel transparente por pantalla que, mientras el modo
 * lápiz está encendido, SÍ recibe el ratón y la pluma.
 *
 * Es la diferencia grande con el overlay del láser, y la razón de que sean dos
 * clases y no una con una bandera: el del láser es click-through SIEMPRE
 * (invariante 1 de la app) y aquí la superficie tiene que quedarse el trazo. Los
 * dos modos son EXCLUYENTES por diseño — uno esconde el cursor y deja pasar el
 * clic, el otro lo captura — y mezclarlos en una sola ventana era la forma
 * segura de romper el invariante del láser sin querer.
 *
 * ── POR QUÉ EL PANEL PUEDE SER `key` SIN ACTIVAR LA APP ─────────────────────
 * `.nonactivatingPanel` existe justo para esto: recibe teclado sin traer la app
 * al frente. Así hay atajos de UNA letra (E, P, M, 1..5) sin tocar el
 * `CGEventTap`, que sigue siendo `.listenOnly` y jamás se traga una tecla
 * (invariante 3). Un tap que consumiera letras se las robaría a la app de
 * debajo aunque no estuvieras dibujando.
 */
final class PizarraOverlayView: NSView {

    weak var controller: PizarraController?
    /// Origen global de la pantalla que cubre esta vista.
    var screenOrigin: CGPoint = .zero

    private var trackingAreaPropia: NSTrackingArea?
    private var puntero: CGPoint?

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: pintar
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Se pintan los trazos que TOCAN el rectángulo sucio, no todos. Con el
     * camino ya cacheado en cada `Trazo`, rellenar es barato; recalcular el
     * motor no lo sería, y por eso el contorno vive en el trazo y no aquí.
     *
     * El trazo VIVO se recalcula entero en cada fotograma —0.23 ms para 600
     * muestras, medido en sfmap— y ésa es exactamente la garantía de que el
     * borrador y el trazo guardado son el MISMO dibujo: no hay dos caminos.
     */
    override func draw(_ dirtyRect: NSRect) {
        guard let ctrl = controller, let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.saveGState()
        ctx.setShouldAntialias(true)
        // global → local: todo lo demás piensa en coordenadas de escritorio
        ctx.translateBy(x: -screenOrigin.x, y: -screenOrigin.y)
        let sucioGlobal = dirtyRect.offsetBy(dx: screenOrigin.x, dy: screenOrigin.y)

        for t in ctrl.pizarra.trazos where t.caja.intersects(sucioGlobal) {
            guard let cam = t.camino else { continue }
            PintorTinta.pintar(cam, color: t.color, alpha: t.alpha, en: ctx)
        }

        if let vivo = ctrl.trazoVivo, let cam = vivo.camino {
            PintorTinta.pintar(cam, color: vivo.color, alpha: vivo.alpha, en: ctx)
        }

        // El disco de la goma. NO es decoración: el radio que se ve es el que
        // borra (misma decisión que sfmap). Sin él, la mano tiene que APUNTAR
        // en vez de PASAR, que es lo contrario de una goma.
        if ctrl.instrumentoEfectivo == .goma, let p = puntero ?? ctrl.punteroGlobal {
            let r = ctrl.grosorGoma / 2
            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
            ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.setLineWidth(3.0)
            ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30))
            ctx.strokeEllipse(in: CGRect(x: p.x - r - 2, y: p.y - r - 2,
                                         width: r * 2 + 4, height: r * 2 + 4))
        }

        ctx.restoreGState()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el ratón y la pluma
    // ════════════════════════════════════════════════════════════════════════

    private func global(_ e: NSEvent) -> CGPoint {
        let local = convert(e.locationInWindow, from: nil)
        return CGPoint(x: local.x + screenOrigin.x, y: local.y + screenOrigin.y)
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        controller?.empezar(en: global(e), evento: e, gomaForzada: false)
    }
    override func mouseDragged(with e: NSEvent) {
        puntero = global(e)
        controller?.seguir(en: global(e), evento: e)
    }
    override func mouseUp(with e: NSEvent) {
        controller?.terminar()
    }

    /// El botón derecho borra sin cambiar de herramienta: es el gesto que ya
    /// tiene la mano en cualquier tableta, y volver al lápiz no cuesta una tecla.
    override func rightMouseDown(with e: NSEvent) {
        controller?.empezar(en: global(e), evento: e, gomaForzada: true)
    }
    override func rightMouseDragged(with e: NSEvent) {
        puntero = global(e)
        controller?.seguir(en: global(e), evento: e)
    }
    override func rightMouseUp(with e: NSEvent) { controller?.terminar() }

    override func otherMouseDown(with e: NSEvent) {
        controller?.empezar(en: global(e), evento: e, gomaForzada: true)
    }
    override func otherMouseDragged(with e: NSEvent) { rightMouseDragged(with: e) }
    override func otherMouseUp(with e: NSEvent) { controller?.terminar() }

    override func mouseMoved(with e: NSEvent) {
        let p = global(e)
        let antes = puntero
        puntero = p
        controller?.punteroGlobal = p
        // Solo se repinta donde estaba el disco y donde está: mover el ratón
        // por la pantalla no puede costar un repintado entero.
        if controller?.instrumentoEfectivo == .goma {
            let r = (controller?.grosorGoma ?? 28) / 2 + 6
            var zona = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            if let a = antes {
                zona = zona.union(CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2))
            }
            setNeedsDisplay(globalRect: zona)
        }
    }

    override func mouseEntered(with e: NSEvent) {
        // El teclado sigue a la mano: la pantalla donde está el puntero es la
        // que escucha las teclas, o los atajos dejarían de responder al pasar
        // de un monitor a otro.
        if let w = window, w.canBecomeKey, !w.isKeyWindow { w.makeKey() }
        window?.makeFirstResponder(self)
    }

    override func mouseExited(with e: NSEvent) {
        if controller?.instrumentoEfectivo == .goma, let p = puntero {
            let r = (controller?.grosorGoma ?? 28) / 2 + 6
            setNeedsDisplay(globalRect: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        puntero = nil
    }

    /// La rueda del ratón y el DIAL de la tableta mueven el grosor. En la Huion
    /// el dial llega como un `scrollWheel` normal, así que no hay nada especial
    /// que detectar: se anda por la escalera del instrumento activo.
    override func scrollWheel(with e: NSEvent) {
        let dy = e.scrollingDeltaY
        guard abs(dy) > 0.01 else { return }
        controller?.moverGrosor(pasos: dy > 0 ? 1 : -1)
    }

    /// Voltear la pluma ES la goma. La Kamvas avisa por proximidad qué punta
    /// está encima, y preguntarle al usuario que además pulse una tecla sería
    /// pedirle que repita algo que el instrumento ya dijo.
    override func tabletProximity(with e: NSEvent) {
        guard e.subtype == .tabletProximity else { return }
        controller?.plumaVolteada = (e.pointingDeviceType == .eraser)
    }

    override func keyDown(with e: NSEvent) {
        if controller?.tecla(e) != true { super.keyDown(with: e) }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: seguimiento y repintado
    // ════════════════════════════════════════════════════════════════════════

    /// El área de seguimiento se instala AL ENTRAR EN LA VENTANA, no en el
    /// primer dibujado. Antes nacía en `updateTrackingAreas`, que AppKit solo
    /// llama cuando hay que redibujar — y una pizarra vacía no se redibuja
    /// nunca: el disco de la goma no seguía al cursor hasta el primer trazo.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaPropia { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .mouseEnteredAndExited,
                                         .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaPropia = t
    }

    override func resetCursorRects() {
        // Cruz fina: la punta de la pluma tiene que verse dónde muerde. El
        // cursor del sistema NO se oculta — el láser sí lo hace y ahí vive el
        // riesgo del contador desbalanceado; aquí no hace falta correrlo.
        addCursorRect(bounds, cursor: .crosshair)
    }

    func setNeedsDisplay(globalRect: CGRect) {
        let local = globalRect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        setNeedsDisplay(local.insetBy(dx: -3, dy: -3))
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: la ventana
// ════════════════════════════════════════════════════════════════════════════

/// Panel de pizarra: cubre una pantalla, captura el ratón mientras se dibuja y
/// vuelve a ser click-through al congelar la tinta.
final class PizarraOverlayWindow: NSPanel {

    let vista = PizarraOverlayView()

    /// Mientras es `false` la ventana no puede ser `key`: es lo que evita que
    /// una pizarra congelada (click-through, con tinta visible) siga
    /// quedándose el teclado de la app en la que Daniel está trabajando.
    var capturaTeclado = false

    init(screen: NSScreen, controller: PizarraController) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        /* ⚠️ EL NIVEL VA AL FINAL, Y NO ES ESTILO: `isFloatingPanel = true`
         * REESCRIBE el nivel a `.floating` (3). Puesto antes, la pizarra se
         * quedaba en 3 en vez de 5 —justo empatada con el láser— y el fallo era
         * invisible a ojo: la ventana se veía bien porque no había nada más a
         * ese nivel con quien competir. Lo cazó la prueba de humo, no la vista.
         *
         * Justo por encima del láser y por debajo de la barra de menú (que vive
         * en `.mainMenu` = 24): anotar no puede secuestrar el menú del sistema. */
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)

        vista.frame = NSRect(origin: .zero, size: screen.frame.size)
        vista.autoresizingMask = [.width, .height]
        vista.controller = controller
        vista.screenOrigin = screen.frame.origin
        contentView = vista

        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { capturaTeclado }
    override var canBecomeMain: Bool { false }

    func setNeedsDisplay(globalRect: CGRect) { vista.setNeedsDisplay(globalRect: globalRect) }
    func repintarTodo() { vista.setNeedsDisplay(vista.bounds) }
}
