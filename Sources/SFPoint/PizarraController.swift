import AppKit

/**
 * EL MODO LÁPIZ — la mano, el modo y las teclas.
 *
 * Tres modos y nada más:
 *
 *   apagado   → no hay ventanas, no hay listeners, no hay tinta. ~0% CPU.
 *   dibujando → los paneles capturan ratón/pluma/teclado. Se dibuja.
 *   congelada → la tinta se queda VISIBLE y los paneles vuelven a ser
 *               click-through: puedes seguir usando la app de debajo con la
 *               anotación encima. Es lo que convierte esto en una pizarra para
 *               explicar, y no solo en un garabato de un rato.
 *
 * `⌥L` entra y sale. `⌥⇧L` congela. `Esc` sale y limpia.
 */
@MainActor
final class PizarraController {

    enum Modo { case apagado, dibujando, congelada }

    private(set) var modo: Modo = .apagado
    let pizarra = Pizarra()

    // MARK: instrumento

    private(set) var instrumento: Instrumento = .lapiz
    private(set) var color: TintaColor = .morado
    /// Un grosor por instrumento: cambiar de lápiz a goma y volver no puede
    /// perder el calibre que ya tenías puesto.
    private var grosores: [Instrumento: Double] = [
        .lapiz: Instrumento.lapiz.grosorPorDefecto,
        .marcador: Instrumento.marcador.grosorPorDefecto,
        .goma: Instrumento.goma.grosorPorDefecto,
    ]

    /// La pluma volteada manda sobre la herramienta elegida, mientras dure.
    var plumaVolteada = false {
        didSet {
            guard plumaVolteada != oldValue else { return }
            repintarPunteroYAviso()
            paleta.refrescar()   // voltear la pluma se VE en la paleta
        }
    }

    var instrumentoEfectivo: Instrumento { plumaVolteada ? .goma : instrumento }
    var grosorGoma: Double { grosores[.goma] ?? 28 }
    var grosorActual: Double { grosores[instrumentoEfectivo] ?? 6 }

    // MARK: trazo en curso

    private(set) var trazoVivo: Trazo?
    private var puntos: [PuntoTinta] = []
    private var inicioTrazo: TimeInterval = 0
    private var borrando = false
    private var borroAlgo = false
    var punteroGlobal: CGPoint?

    /// Se apaga la fusión de eventos mientras dura el trazo para que la Kamvas
    /// entregue sus ~260 muestras/s en vez de las ~60 a las que macOS las
    /// agrupa. Se restaura en `soltarGesto()`, que TODOS los caminos de salida
    /// atraviesan —incluido salirse con Esc a media línea—: por esa puerta se
    /// quedaba apagada para el resto de la vida del proceso en sfmap, cobrándole
    /// eventos de más a cada arrastre de toda la máquina.
    private var fusionApagada = false

    /// Solo para la verificación de humo: las ventanas reales, para poder
    /// preguntarles si de verdad están en pantalla y si tienen el teclado.
    var ventanasParaPrueba: [PizarraOverlayWindow] { ventanas }
    /// La pantalla donde se abrió la pizarra. **UNA sola, no todas.**
    ///
    /// Daniel: *"si funciona en una pantalla, solo sea en una, no en las 2; el
    /// foco no tenderá a ser en ambas"*. Y tiene razón operativa: capturar el
    /// ratón en los dos monitores convierte el segundo —donde estás leyendo el
    /// guion, el chat o el código que vas a anotar— en una superficie muerta.
    /// Se anota en la pantalla que estás mirando; la otra sigue siendo tuya.
    ///
    /// Se elige por dónde está el cursor AL ENTRAR. Para moverla a la otra
    /// pantalla: sales (⌥L), pasas el cursor y vuelves a entrar.
    private(set) var pantallaActiva: NSScreen?
    private var ventanas: [PizarraOverlayWindow] = []
    private let hud = HUDPizarra()
    let paleta = PaletaPizarra()
    /// El humo de verificación no puede pintar avisos en la pantalla de Daniel.
    var silencioso = false

    var onModoChange: ((Modo) -> Void)?

    init() {
        paleta.ctrl = self
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rehacerVentanas() }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: modo
    // ════════════════════════════════════════════════════════════════════════

    /// ⌥L
    func alternar() {
        switch modo {
        case .apagado:   entrar()
        case .dibujando: salir()
        case .congelada: entrar()      // vuelve a dibujar SOBRE lo que ya había
        }
    }

    /// ⌥⇧L
    func alternarCongelado() {
        switch modo {
        case .apagado:   break                       // no hay nada que congelar
        case .dibujando: pizarra.estaVacia ? salir() : congelar()
        case .congelada: salir()
        }
    }

    func entrar() {
        soltarGesto()
        let quiero = pantallaDelCursor()
        // Si cambió la pantalla bajo el cursor, la ventana se muda con él.
        if ventanas.isEmpty || pantallaActiva !== quiero { construirVentanas(en: quiero) }
        modo = .dibujando
        for v in ventanas {
            v.capturaTeclado = true
            v.ignoresMouseEvents = false
            v.orderFrontRegardless()
            v.repintarTodo()
        }
        // El teclado va a la pantalla donde está la mano.
        ventanaBajoElPuntero()?.makeKey()
        if !silencioso { paleta.mostrar(en: ventanaBajoElPuntero()?.screen) }
        avisar("\(instrumentoEfectivo.nombre) · \(color.nombre) · \(Int(grosorActual))")
        onModoChange?(modo)
    }

    private func congelar() {
        soltarGesto()
        modo = .congelada
        for v in ventanas {
            v.capturaTeclado = false
            v.ignoresMouseEvents = true      // la app de debajo vuelve a recibir el clic
            v.orderFrontRegardless()
            v.repintarTodo()
        }
        // La paleta se queda: desde ella se vuelve a dibujar de un clic, sin
        // tener que acordarse del atajo.
        paleta.refrescar()
        avisar("Tinta congelada · ⌥L para seguir dibujando")
        onModoChange?(modo)
    }

    func salir() {
        soltarGesto()
        modo = .apagado
        pizarra.limpiar()
        punteroGlobal = nil
        plumaVolteada = false
        hud.ocultar()
        paleta.ocultar()
        for v in ventanas { v.capturaTeclado = false; v.orderOut(nil) }
        onModoChange?(modo)
    }

    private func pantallaDelCursor() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main
    }

    private func construirVentanas(en pantalla: NSScreen?) {
        ventanas.forEach { $0.orderOut(nil) }
        ventanas.removeAll()
        guard let pantalla else { return }
        pantallaActiva = pantalla
        ventanas = [PizarraOverlayWindow(screen: pantalla, controller: self)]
    }

    private func rehacerVentanas() {
        let estaba = modo
        // Si desconectaron la pantalla donde vivía, se va a la del cursor.
        let sigue = pantallaActiva.flatMap { p in NSScreen.screens.first { $0 === p } }
        construirVentanas(en: sigue ?? pantallaDelCursor())
        switch estaba {
        case .apagado:   break
        case .dibujando: entrar()
        case .congelada: congelar()
        }
    }

    private func ventanaBajoElPuntero() -> PizarraOverlayWindow? {
        let p = NSEvent.mouseLocation
        return ventanas.first { $0.frame.contains(p) } ?? ventanas.first
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el gesto
    // ════════════════════════════════════════════════════════════════════════

    func empezar(en p: CGPoint, evento e: NSEvent, gomaForzada: Bool) {
        guard modo == .dibujando else { return }
        paleta.cerrarTira()
        punteroGlobal = p
        borrando = gomaForzada || instrumentoEfectivo == .goma

        if borrando {
            pizarra.abrirPaso()
            borroAlgo = false
            borrar(en: p)
            return
        }

        NSEvent.isMouseCoalescingEnabled = false
        fusionApagada = true
        inicioTrazo = e.timestamp
        puntos = [punto(e, p)]
        actualizarVivo()
        repintar(cajaDe(puntos.suffix(2)))
    }

    func seguir(en p: CGPoint, evento e: NSEvent) {
        guard modo == .dibujando else { return }
        punteroGlobal = p

        if borrando { borrar(en: p); return }
        guard !puntos.isEmpty else { return }

        puntos.append(punto(e, p))
        if puntos.count > Tinta.MAX_MUESTRAS { puntos.removeFirst() }
        actualizarVivo()
        // Solo se ensucia la COLA. El motor es incremental de hecho: el filtro
        // no reescribe lo ya trazado salvo el afilado de salida, que vive en
        // el último medio diámetro. Repintar la pantalla entera por cada
        // muestra de la pluma sería pagar 260 pantallas por segundo.
        repintar(cajaDe(puntos.suffix(10)))
    }

    func terminar() {
        guard modo == .dibujando else { return soltarGesto() }

        if borrando {
            if !borroAlgo { pizarra.cancelarPaso() }
            soltarGesto()
            return
        }

        if puntos.count >= 1 {
            let t = Trazo(puntos: puntos, color: color.color,
                          grosor: grosorActual, marcador: instrumento == .marcador)
            pizarra.agregar(t)
            repintar(t.caja)
            paleta.refrescar()   // deshacer y limpiar ya tienen de dónde tirar
        }
        soltarGesto()
    }

    /// TODA salida del gesto pasa por aquí. Ver `fusionApagada`.
    private func soltarGesto() {
        if fusionApagada { NSEvent.isMouseCoalescingEnabled = true; fusionApagada = false }
        puntos.removeAll()
        trazoVivo = nil
        borrando = false
    }

    private func actualizarVivo() {
        // Crear el `Trazo` es barato: el contorno se calcula PEREZOSAMENTE, la
        // primera vez que alguien lo pinta. Así el motor corre una vez por
        // fotograma y no una vez por muestra de la pluma.
        trazoVivo = Trazo(puntos: puntos, color: color.color,
                          grosor: grosorActual, marcador: instrumento == .marcador)
    }

    /**
     * Un punto con TODO lo que el evento sabe. Igual que sfmap, con una
     * diferencia de convenio que hay que dejar escrita: allá la Y del lienzo va
     * hacia ABAJO (convenio del canvas web) y por eso invierte `tilt.y`; aquí
     * las coordenadas son las del escritorio de AppKit, con la Y hacia ARRIBA
     * —la misma que el evento—, así que la inclinación entra SIN girar.
     */
    private func punto(_ e: NSEvent, _ p: CGPoint) -> PuntoTinta {
        var q = PuntoTinta(x: redondear(p.x, 2), y: redondear(p.y, 2),
                           // `pressure` de un ratón llega constante (1.0) y el
                           // motor ya lo detecta por VARIANZA, no por el tipo de
                           // puntero (`Tinta.presionReal`): no hay que inventar
                           // nada aquí ni preguntar qué dispositivo es.
                           p: redondear(Double(e.pressure), 4))
        q.t = redondear(max(0, (e.timestamp - inicioTrazo) * 1000), 1)
        if e.subtype == .tabletPoint {
            let t = e.tilt
            q.ix = redondear(Double(t.x), 4)
            q.iy = redondear(Double(t.y), 4)
        }
        return q
    }

    private func redondear(_ v: Double, _ d: Int) -> Double {
        let f = pow(10.0, Double(d))
        return (v * f).rounded() / f
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: la goma
    // ════════════════════════════════════════════════════════════════════════

    private func borrar(en p: CGPoint) {
        let r = grosorGoma / 2
        let tocados = pizarra.alcanzados(centro: p, radio: r)
        guard !tocados.isEmpty else { return }
        var zona = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        for t in pizarra.trazos where tocados.contains(ObjectIdentifier(t)) {
            zona = zona.union(t.caja)
        }
        if pizarra.quitar(tocados) {
            borroAlgo = true
            repintar(zona)
            paleta.refrescar()
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: teclas
    // ════════════════════════════════════════════════════════════════════════

    /// Devuelve `true` si la tecla era nuestra. El panel solo captura teclado
    /// mientras se dibuja, así que fuera del modo esto ni se llama.
    func tecla(_ e: NSEvent) -> Bool {
        guard modo == .dibujando else { return false }
        let cmd = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)
        let c = (e.charactersIgnoringModifiers ?? "").lowercased()

        if e.keyCode == Config.vkEsc { salir(); return true }

        // Lo que lleva ⌥ es del tap global (⌥L, ⌥⇧L, ⌥P). Se consume sin hacer
        // nada para que el panel no lo interprete DOS veces —⌥L acababa
        // saliendo del modo y eligiendo el lápiz a la vez— ni suene el beep de
        // tecla no manejada.
        if e.modifierFlags.contains(.option) { return true }

        if cmd, c == "z" {
            shift ? rehacer() : deshacer()
            avisar(shift ? "Rehacer" : "Deshacer")
            return true
        }
        guard !cmd else { return false }

        /*
         * ⌃P LÁPIZ · ⌃M MARCADOR · ⌃E GOMA — LOS MISMOS QUE SFMAP.
         *
         * Daniel tiene los botones del lápiz físico de la Kamvas configurados
         * así (sfmap, 26 ago: *"así configuraré los botones en el lápiz físico
         * de la tableta"*), y el mismo lápiz tiene que hacer lo mismo en las dos
         * apps o el músculo se parte en dos. Van con CONTROL y no sueltas por la
         * razón de allá: una tableta manda su combinación sin que haya un dedo
         * cerca del teclado, así que un atajo para hardware tiene que ser
         * imposible de pulsar por accidente mientras se escribe.
         */
        if e.modifierFlags.contains(.control) {
            switch c {
            case "p": elegir(.lapiz);    return true
            case "m": elegir(.marcador); return true
            case "e": elegir(.goma);     return true
            default: return false
            }
        }

        switch c {
        case "p", "l": elegir(.lapiz);    return true
        case "m":      elegir(.marcador); return true
        case "e":      elegir(.goma);     return true
        case "c":      limpiar();         return true
        case "f":      alternarCongelado(); return true
        // Esconde la paleta sin salir del modo: cuando la cámara está grabando,
        // una barra flotante en cuadro es basura visual. Vuelve con la misma tecla.
        case "h":      paleta.alternarVisible(en: ventanaBajoElPuntero()?.screen); return true
        // La rueda de abajo de la Huion puede mandar `[ ]` o `, .` según cómo
        // esté mapeada en su app. sfmap acepta las cuatro; aquí también, o el
        // mismo dial haría cosas distintas en cada app.
        case "[", ",":  moverGrosor(pasos: -1); return true
        case "]", ".":  moverGrosor(pasos: 1);  return true
        case "1", "2", "3", "4", "5":
            if let n = Int(c), let col = TintaColor(rawValue: n - 1) { elegir(col) }
            return true
        default: break
        }

        // Retroceso y suprimir limpian: es lo que la mano intenta primero.
        if e.keyCode == 51 || e.keyCode == 117 { limpiar(); return true }
        return false
    }

    func elegir(_ i: Instrumento) {
        // Elegir instrumento con la tinta congelada es querer seguir dibujando.
        if modo == .congelada { entrar() }
        instrumento = i
        plumaVolteada = false
        avisar("\(i.nombre) · \(Int(grosorActual))")
        repintarPunteroYAviso()
        paleta.refrescar()
    }

    func elegir(_ c: TintaColor) {
        if modo == .congelada { entrar() }
        color = c
        if instrumento == .goma { instrumento = .lapiz }   // pedir color es pedir lápiz
        avisar("\(instrumento.nombre) · \(c.nombre) · \(Int(grosorActual))")
        paleta.refrescar()
    }

    func moverGrosor(pasos: Int) {
        let i = instrumentoEfectivo
        let nuevo = Tinta.grosorAjustado(grosores[i] ?? i.grosorPorDefecto,
                                         pasos: pasos, escalera: i.escalera)
        guard nuevo != grosores[i] else { return }
        grosores[i] = nuevo
        paleta.refrescar()
        avisar("\(i.nombre) · \(Int(nuevo))")
        if i == .goma, let p = punteroGlobal {
            let r = nuevo / 2 + 8
            repintar(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

    /// Poner un peldaño CONCRETO. Es lo que hace la tira: elegir, no contar.
    func ponerGrosor(_ g: Double) {
        let i = instrumentoEfectivo
        guard grosores[i] != g else { return }
        grosores[i] = g
        paleta.refrescar()
        if i == .goma, let p = punteroGlobal {
            let r = max(g, grosorGoma) / 2 + 10
            repintar(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

    func limpiar() {
        guard !pizarra.estaVacia else { return }
        pizarra.limpiar()
        repintarTodo()
        paleta.refrescar()
        avisar("Pizarra limpia")
    }

    func deshacer() {
        pizarra.deshacer()
        repintarTodo()
        paleta.refrescar()
    }

    func rehacer() {
        pizarra.rehacer()
        repintarTodo()
        paleta.refrescar()
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: pintar
    // ════════════════════════════════════════════════════════════════════════

    private func cajaDe<C: Collection>(_ pts: C) -> CGRect where C.Element == PuntoTinta {
        guard let f = pts.first else { return .null }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for q in pts {
            minX = min(minX, q.x); maxX = max(maxX, q.x)
            minY = min(minY, q.y); maxY = max(maxY, q.y)
        }
        // El ensanche de la presión más el afilado de salida, que se mueve con
        // la cola del trazo. Generoso a propósito: un margen corto deja una
        // muesca en el borde que solo se ve cuando ya está pintada.
        let pad = Tinta.diametro(Tinta.Opciones(grosor: grosorActual,
                                                marcador: instrumento == .marcador))
                  * Tinta.ANCHO_MAX + 6
        return CGRect(x: minX - pad, y: minY - pad,
                      width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
    }

    private func repintar(_ global: CGRect) {
        guard !global.isNull else { return }
        for v in ventanas where v.isVisible && v.frame.intersects(global) {
            v.setNeedsDisplay(globalRect: global)
        }
    }

    private func repintarTodo() {
        for v in ventanas where v.isVisible { v.repintarTodo() }
    }

    private func repintarPunteroYAviso() {
        guard let p = punteroGlobal else { return }
        let r = max(grosorGoma, 40) / 2 + 10
        repintar(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    /// El HUD solo habla cuando la paleta NO está a la vista. Con las dos, el
    /// mismo dato aparecía dos veces y el aviso pasaba de acuse a ruido.
    private func avisar(_ texto: String) {
        guard modo != .apagado, !silencioso, !paleta.estaVisible else { return }
        hud.mostrar(texto, color: instrumentoEfectivo == .goma ? nil : color.color,
                    en: ventanaBajoElPuntero()?.screen ?? NSScreen.main)
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: el aviso
// ════════════════════════════════════════════════════════════════════════════

/**
 * El HUD. NO es un panel de ajustes —el `CLAUDE.md` de esta app los prohíbe con
 * razón: en la v1 nadie los usó y cada uno era superficie que podía romperse—.
 * Es un ACUSE: aparece cuando cambias algo, dice qué quedó puesto y se va solo.
 * Sin él, un atajo de una letra es fe ciega.
 */
@MainActor
private final class HUDPizarra {

    private var panel: NSPanel?
    private let etiqueta = NSTextField(labelWithString: "")
    private let punto = NSView()
    private var apagon: Timer?

    private func construir() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false

        let fondo = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 260, height: 40))
        fondo.material = .hudWindow
        fondo.state = .active
        fondo.blendingMode = .behindWindow
        fondo.wantsLayer = true
        fondo.layer?.cornerRadius = 12
        fondo.layer?.masksToBounds = true
        fondo.autoresizingMask = [.width, .height]

        punto.wantsLayer = true
        punto.layer?.cornerRadius = 5
        punto.frame = NSRect(x: 14, y: 15, width: 10, height: 10)
        fondo.addSubview(punto)

        etiqueta.font = .systemFont(ofSize: 13, weight: .medium)
        etiqueta.textColor = .white
        etiqueta.frame = NSRect(x: 32, y: 11, width: 214, height: 18)
        etiqueta.alignment = .left
        fondo.addSubview(etiqueta)

        p.contentView = fondo
        return p
    }

    func mostrar(_ texto: String, color: NSColor?, en pantalla: NSScreen?) {
        let p = panel ?? construir()
        panel = p
        etiqueta.stringValue = texto
        punto.layer?.backgroundColor = (color ?? NSColor(white: 0.85, alpha: 1)).cgColor
        punto.isHidden = false

        let ancho = max(150, etiqueta.attributedStringValue.size().width + 60)
        let pantalla = pantalla ?? NSScreen.main
        guard let f = pantalla?.frame else { return }
        p.setFrame(NSRect(x: f.midX - ancho / 2, y: f.minY + 90, width: ancho, height: 40),
                   display: false)
        etiqueta.frame = NSRect(x: 32, y: 11, width: ancho - 44, height: 18)

        p.alphaValue = 1
        p.orderFrontRegardless()

        apagon?.invalidate()
        let t = Timer(timeInterval: 1.4, repeats: false) { _ in
            Task { @MainActor in
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.35
                    p.animator().alphaValue = 0
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        apagon = t
    }

    func ocultar() {
        apagon?.invalidate()
        panel?.orderOut(nil)
    }
}
