import AppKit

/**
 * VERIFICACIÓN HEADLESS DE LA PIZARRA — sin abrir una sola ventana.
 *
 * Existe por dos reglas de la casa que se pagan solas:
 *
 *  · **Nada emerge mientras Daniel trabaja.** Una app que se abre para
 *    "probarse" le roba el foco; lo que se puede medir off-screen, se mide.
 *  · **Un motor de tinta no se juzga con adjetivos.** El banco de sfmap
 *    (`banco/trazos.json`: 32 trazos REALES de su Kamvas + 10 sintéticos) se
 *    pinta aquí con el MISMO rasterizador que usa la pantalla (`PintorTinta`),
 *    así que lo que sale del PNG es lo que sale del panel.
 *
 *   ./SFPoint --banco-tinta /tmp/banco-lapiz     # hoja PNG + tiempos
 *   ./SFPoint --pizarra-test                     # modelo: goma, deshacer, escaleras
 */
enum PizarraTest {

    static let bancoPorDefecto =
        NSString(string: "~/Developer/software/sfmap/banco/trazos.json").expandingTildeInPath

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el banco
    // ════════════════════════════════════════════════════════════════════════

    struct Caso {
        let nombre: String
        let trazos: [Trazo]
    }

    static func cargar(_ ruta: String) -> [Caso]? {
        guard let data = FileManager.default.contents(atPath: ruta),
              let raiz = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casos = raiz["casos"] as? [[String: Any]] else { return nil }

        return casos.compactMap { c in
            guard let nombre = c["nombre"] as? String,
                  let trazos = c["trazos"] as? [[String: Any]] else { return nil }
            let tt: [Trazo] = trazos.compactMap { t in
                guard let pts = t["puntos"] as? [[String: Any]] else { return nil }
                let grosor = (t["size"] as? Double) ?? 4
                let marcador = (t["highlighter"] as? Bool) ?? false
                let ox = (t["x"] as? Double) ?? 0, oy = (t["y"] as? Double) ?? 0
                var puntos: [PuntoTinta] = []
                for p in pts {
                    guard let x = p["x"] as? Double, let y = p["y"] as? Double else { continue }
                    var q = PuntoTinta(x: x + ox, y: y + oy, p: (p["pressure"] as? Double) ?? 0.5)
                    if let ix = p["tiltX"] as? Double { q.ix = ix }
                    if let iy = p["tiltY"] as? Double { q.iy = iy }
                    if let tm = p["t"] as? Double { q.t = tm }
                    puntos.append(q)
                }
                guard !puntos.isEmpty else { return nil }
                return Trazo(puntos: puntos, color: marcador ? Config.ambar : Config.morado,
                             grosor: grosor, marcador: marcador)
            }
            return tt.isEmpty ? nil : Caso(nombre: nombre, trazos: tt)
        }
    }

    static func banco(dir: String, ruta: String) -> Int32 {
        guard let casos = cargar(ruta) else {
            FileHandle.standardError.write("banco: no pude leer \(ruta)\n".data(using: .utf8)!)
            return 1
        }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        print("=== BANCO DE TINTA — SFPoint (motor portado de sfmap) ===")
        print("fuente: \(ruta)")
        print("")
        print(String(format: "%-20s %7s %8s %10s %10s",
                     ("caso" as NSString).utf8String!, ("trazos" as NSString).utf8String!,
                     ("puntos" as NSString).utf8String!, ("geom ms" as NSString).utf8String!,
                     ("pinta ms" as NSString).utf8String!))

        var totalGeom = 0.0, totalPinta = 0.0, totalPuntos = 0
        for caso in casos {
            // Caja común a todos los trazos del caso, con margen para el ancho.
            var caja = CGRect.null
            let t0 = CACurrentMediaTime()
            for t in caso.trazos { caja = caja.union(t.caja) }
            let geom = (CACurrentMediaTime() - t0) * 1000

            let margen = 12.0
            let w = max(16, Int(caja.width + margen * 2)), h = max(16, Int(caja.height + margen * 2))
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { continue }
            // Fondo grafito: la tinta de la pizarra vive sobre lo que haya en la
            // pantalla, y sobre blanco puro el morado miente.
            ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setShouldAntialias(true)
            ctx.translateBy(x: -caja.minX + margen, y: -caja.minY + margen)

            let t1 = CACurrentMediaTime()
            for t in caso.trazos {
                guard let cam = t.camino else { continue }
                PintorTinta.pintar(cam, color: t.color, alpha: t.alpha, en: ctx)
            }
            let pinta = (CACurrentMediaTime() - t1) * 1000

            let puntos = caso.trazos.reduce(0) { $0 + $1.puntos.count }
            totalGeom += geom; totalPinta += pinta; totalPuntos += puntos
            print(String(format: "%-20@ %7d %8d %10.3f %10.3f",
                         caso.nombre as NSString, caso.trazos.count, puntos, geom, pinta))

            if let img = ctx.makeImage(),
               let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(caso.nombre).png"))
            }
        }

        print("")
        print(String(format: "TOTAL  %d casos · %d puntos · geometría %.2f ms · pintado %.2f ms",
                     casos.count, totalPuntos, totalGeom, totalPinta))
        print("PNGs en \(dir)")
        print("")
        return medirFotograma(casos: casos)
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el presupuesto del fotograma
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Lo que de verdad importa para que se sienta "smooth": cuánto cuesta UN
     * fotograma con la pizarra llena y un trazo vivo encima. El presupuesto es
     * 8.3 ms a 120 Hz (16.6 a 60). Y se mide lo que la pantalla hace: rellenar
     * los caminos ya cacheados de los trazos terminados + recalcular el vivo.
     */
    static func medirFotograma(casos: [Caso]) -> Int32 {
        let todos = casos.flatMap(\.trazos)
        guard !todos.isEmpty else { return 1 }

        // Un trazo vivo largo, del tamaño del más largo del banco.
        let vivoPuntos = todos.max(by: { $0.puntos.count < $1.puntos.count })!.puntos
        guard let ctx = CGContext(data: nil, width: 3840, height: 2160, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        ctx.setShouldAntialias(true)

        // Precalienta las cachés de contorno (eso pasa una vez por trazo, al
        // terminarlo, no en cada fotograma).
        for t in todos { _ = t.camino }

        var repintado: [Double] = []
        for _ in 0..<5 {
            let t0 = CACurrentMediaTime()
            for t in todos {
                guard let cam = t.camino else { continue }
                PintorTinta.pintar(cam, color: t.color, alpha: t.alpha, en: ctx)
            }
            repintado.append((CACurrentMediaTime() - t0) * 1000)
        }

        var vivo: [Double] = []
        for _ in 0..<10 {
            let t0 = CACurrentMediaTime()
            let t = Trazo(puntos: vivoPuntos, color: Config.morado, grosor: 6, marcador: false)
            if let cam = t.camino { PintorTinta.pintar(cam, color: t.color, alpha: 1, en: ctx) }
            vivo.append((CACurrentMediaTime() - t0) * 1000)
        }

        func p(_ v: [Double]) -> String {
            let s = v.sorted()
            return String(format: "media %.2f · p95 %.2f", v.reduce(0,+) / Double(v.count),
                          s[min(s.count - 1, Int(Double(s.count) * 0.95))])
        }

        print("=== PRESUPUESTO DEL FOTOGRAMA (8.3 ms a 120 Hz) ===")
        print("repintado COMPLETO de \(todos.count) trazos (4K):   \(p(repintado)) ms")
        print("trazo VIVO de \(vivoPuntos.count) muestras, motor + relleno: \(p(vivo)) ms")
        print("")
        print("NOTA: la pantalla real repinta solo el rectángulo sucio de la cola del")
        print("trazo, no la pizarra entera — el número de arriba es el peor caso absoluto.")
        return 0
    }

    // ════════════════════════════════════════════════════════════════════════
    // MARK: el modelo
    // ════════════════════════════════════════════════════════════════════════

    @MainActor
    static func modelo() -> Int32 {
        var fallos = 0
        func check(_ nombre: String, _ ok: Bool, _ detalle: String = "") {
            print("\(ok ? "  ok  " : "  FALLA ") \(nombre)\(detalle.isEmpty ? "" : " — \(detalle)")")
            if !ok { fallos += 1 }
        }

        print("=== PIZARRA — modelo ===")
        let p = Pizarra()

        func recta(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, n: Int = 24) -> Trazo {
            let pts = (0...n).map { i -> PuntoTinta in
                let t = Double(i) / Double(n)
                return PuntoTinta(x: x0 + (x1 - x0) * t, y: y0 + (y1 - y0) * t,
                                  p: 0.15 + 0.4 * sin(t * .pi), t: Double(i) * 4)
            }
            return Trazo(puntos: pts, color: Config.morado, grosor: 6, marcador: false)
        }

        let a = recta(100, 100, 400, 100)
        let b = recta(100, 300, 400, 300)
        p.agregar(a); p.agregar(b)
        check("dos trazos entran", p.trazos.count == 2)

        // La goma alcanza lo que TOCA y nada más.
        let lejos = p.alcanzados(centro: CGPoint(x: 250, y: 200), radio: 10)
        check("la goma NO se lleva lo que no toca", lejos.isEmpty)
        let cerca = p.alcanzados(centro: CGPoint(x: 250, y: 100), radio: 14)
        check("la goma alcanza el trazo de debajo", cerca.count == 1)

        // El disco es la verdad: un radio grande alcanza los dos.
        let ambos = p.alcanzados(centro: CGPoint(x: 250, y: 200), radio: 110)
        check("un disco grande alcanza los dos", ambos.count == 2, "alcanzó \(ambos.count)")

        p.abrirPaso()
        _ = p.quitar(cerca)
        check("borrar quita uno", p.trazos.count == 1)
        p.deshacer()
        check("deshacer devuelve el borrado", p.trazos.count == 2)
        p.rehacer()
        check("rehacer lo vuelve a quitar", p.trazos.count == 1)

        p.limpiar()
        check("limpiar deja la pizarra vacía", p.estaVacia)
        p.deshacer()
        check("deshacer un limpiar lo devuelve todo", p.trazos.count == 1)

        // Un paso cancelado no deja huella: un deshacer que no deshace nada es
        // peor que no tenerlo.
        let antes = p.puedeDeshacer
        p.abrirPaso(); p.cancelarPaso()
        check("un paso cancelado no ensucia la historia", p.puedeDeshacer == antes)

        // Las escaleras: cada instrumento anda por la suya y con tope.
        let g1 = Tinta.grosorAjustado(6, pasos: 1, escalera: Instrumento.lapiz.escalera)
        let g2 = Tinta.grosorAjustado(26, pasos: 5, escalera: Instrumento.lapiz.escalera)
        let g3 = Tinta.grosorAjustado(8, pasos: -9, escalera: Instrumento.goma.escalera)
        check("la escalera del lápiz sube un peldaño", g1 == 9, "dio \(g1)")
        check("la escalera tiene tope arriba", g2 == 26, "dio \(g2)")
        check("y tope abajo", g3 == 8, "dio \(g3)")

        // El marcador es translúcido; el lápiz no.
        let marca = Trazo(puntos: a.puntos, color: Config.ambar, grosor: 26, marcador: true)
        check("el marcador es translúcido", marca.alpha < 0.5 && a.alpha == 1.0)

        // Un toque de pluma deja tinta (el motor viejo dejaba la nada).
        let toque = Trazo(puntos: [PuntoTinta(x: 10, y: 10, p: 0.0)], color: Config.morado,
                          grosor: 6, marcador: false)
        check("un toque de pluma deja un punto", toque.camino != nil && !toque.caja.isNull)

        print("")
        print(fallos == 0 ? "TODO EN VERDE" : "\(fallos) FALLO(S)")
        return fallos == 0 ? 0 : 1
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: el humo — el cableado de AppKit, en vivo pero SIN pintar nada
// ════════════════════════════════════════════════════════════════════════════

extension PizarraTest {

    /**
     * Lo único que las pruebas de arriba NO pueden probar: que los paneles
     * existan de verdad sobre la pantalla, que se queden el teclado, y que un
     * evento entrando por `mouseDown/mouseDragged/mouseUp` termine en un trazo.
     *
     * Se hace SIN robarle la pantalla a Daniel: la pizarra entra vacía (un
     * overlay vacío es 100% transparente), el HUD va silenciado, los eventos se
     * construyen y se ENTREGAN A MANO a la vista —no se postean al sistema, así
     * que su cursor no se mueve ni un píxel— y al acabar se limpia todo.
     *
     * Lo que NO prueba, y hay que decirlo: que macOS RUTEE el clic físico a
     * este panel en vez de a la app de abajo. Eso depende de
     * `ignoresMouseEvents` y del nivel de ventana, y solo se confirma con la
     * mano encima. Lo demás, aquí queda medido.
     */
    @MainActor
    static func humo() -> Int32 {
        var fallos = 0
        func check(_ nombre: String, _ ok: Bool, _ detalle: String = "") {
            print("\(ok ? "  ok  " : "  FALLA") \(nombre)\(detalle.isEmpty ? "" : " — \(detalle)")")
            if !ok { fallos += 1 }
        }

        print("=== HUMO — cableado de AppKit ===")
        print("pantallas visibles para este proceso: \(NSScreen.screens.count)")
        guard let pantalla = NSScreen.screens.first else {
            print("  SIN PANTALLAS: este proceso no alcanza el WindowServer.")
            print("  Correr dentro de la sesión gráfica (gate de SFTerm) para que valga.")
            return 3
        }

        let ctrl = PizarraController()
        ctrl.silencioso = true          // sin HUD encima de la pantalla de Daniel
        ctrl.entrar()
        // La paleta sí se comprueba, pero fuera de su vista: se muestra en la
        // esquina inferior de la pantalla y se retira en menos de un segundo.
        ctrl.paleta.mostrar(en: NSScreen.screens.first)

        let ventanas = ctrl.ventanasParaPrueba
        check("UN solo panel, no uno por pantalla", ventanas.count == 1,
              "\(ventanas.count) paneles con \(NSScreen.screens.count) pantallas")
        let bajoCursor = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                         ?? NSScreen.main
        check("y es la pantalla donde está el cursor", ventanas.first?.screen === bajoCursor)
        check("la otra pantalla queda LIBRE",
              !NSScreen.screens.contains { p in p !== bajoCursor
                  && ventanas.contains { $0.screen === p } })
        check("los paneles están en pantalla", ventanas.allSatisfy(\.isVisible))
        check("los paneles capturan el ratón", ventanas.allSatisfy { !$0.ignoresMouseEvents })
        check("el panel puede tomar el teclado", ventanas.allSatisfy(\.canBecomeKey))
        let hayKey = ventanas.contains(where: \.isKeyWindow)
        check("un panel TIENE el teclado", hayKey)
        check("por encima del láser", ventanas.allSatisfy {
            $0.level.rawValue > NSWindow.Level.floating.rawValue + 1 })
        check("por debajo de la barra de menú", ventanas.allSatisfy {
            $0.level.rawValue < NSWindow.Level.mainMenu.rawValue })

        guard let win = ventanas.first(where: { $0.screen == pantalla }) ?? ventanas.first else {
            return 1
        }
        let vista = win.vista
        check("la paleta salió con el modo", ctrl.paleta.estaVisible)
        check("la vista acepta ser primer respondedor", vista.acceptsFirstResponder)
        check("la vista tiene área de seguimiento", !vista.trackingAreas.isEmpty)

        // ── un trazo entero por la puerta real ──────────────────────────────
        func evento(_ tipo: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat,
                    _ presion: Float, _ t: TimeInterval) -> NSEvent? {
            NSEvent.mouseEvent(with: tipo,
                               location: NSPoint(x: x, y: y),
                               modifierFlags: [], timestamp: t,
                               windowNumber: win.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: presion)
        }

        let n = 40
        let base = CGPoint(x: 300, y: 300)
        guard let e0 = evento(.leftMouseDown, base.x, base.y, 0.05, 0) else {
            check("se pudo construir el evento", false); return 1
        }
        vista.mouseDown(with: e0)
        for i in 1...n {
            let t = Double(i) / Double(n)
            let x = base.x + CGFloat(t) * 260
            let y = base.y + CGFloat(sin(t * .pi) * 90)
            // Presión que SUBE y BAJA: si el motor no la viera, el ancho saldría
            // constante y el contraste medido abajo sería 1.0.
            let p = Float(0.05 + 0.55 * sin(t * .pi))
            if let e = evento(.leftMouseDragged, x, y, p, Double(i) * 0.004) {
                vista.mouseDragged(with: e)
            }
        }
        let vivoHabia = ctrl.trazoVivo != nil
        if let e1 = evento(.leftMouseUp, base.x + 260, base.y, 0.02, Double(n) * 0.004) {
            vista.mouseUp(with: e1)
        }

        check("hubo trazo vivo mientras se arrastraba", vivoHabia)
        check("el trazo quedó guardado al soltar", ctrl.pizarra.trazos.count == 1,
              "\(ctrl.pizarra.trazos.count) trazos")
        check("el trazo vivo se soltó", ctrl.trazoVivo == nil)
        check("la fusión de eventos quedó RESTAURADA", NSEvent.isMouseCoalescingEnabled)

        if let t = ctrl.pizarra.trazos.first {
            check("guardó las 41 muestras", t.puntos.count == n + 1, "\(t.puntos.count)")
            check("el trazo tiene caja real", t.caja.width > 200 && t.caja.height > 50,
                  String(format: "%.0fx%.0f", t.caja.width, t.caja.height))
            // El ancho tiene que MODULAR con la presión: se mide el área de tinta
            // contra la de un trazo de presión plana. Si el motor ignorara la
            // presión, las dos áreas serían la misma.
            let plano = Trazo(puntos: t.puntos.map { PuntoTinta(x: $0.x, y: $0.y, p: 0.3, t: $0.t) },
                              color: .white, grosor: t.grosor, marcador: false)
            let a1 = area(t.camino), a2 = area(plano.camino)
            check("la presión modula el ancho", abs(a1 - a2) / max(1, a2) > 0.05,
                  String(format: "%.0f vs %.0f px²", a1, a2))
        }

        // ── la goma, por la misma puerta ────────────────────────────────────
        if let tecla = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: win.windowNumber,
                                        context: nil, characters: "e",
                                        charactersIgnoringModifiers: "e",
                                        isARepeat: false, keyCode: 14) {
            vista.keyDown(with: tecla)
        }
        check("la tecla E cambió a la goma", ctrl.instrumentoEfectivo == .goma,
              ctrl.instrumentoEfectivo.nombre)

        // ── los comandos de la TABLETA, los mismos que sfmap ────────────────
        func tecla(_ ch: String, _ codigo: UInt16, _ mods: NSEvent.ModifierFlags = []) {
            if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods,
                                        timestamp: 0, windowNumber: win.windowNumber,
                                        context: nil, characters: ch,
                                        charactersIgnoringModifiers: ch,
                                        isARepeat: false, keyCode: codigo) {
                vista.keyDown(with: e)
            }
        }
        tecla("p", 35, .control)
        check("⌃P (botón del lápiz físico) → lápiz", ctrl.instrumentoEfectivo == .lapiz,
              ctrl.instrumentoEfectivo.nombre)
        tecla("m", 46, .control)
        check("⌃M → marcador", ctrl.instrumentoEfectivo == .marcador)
        tecla("e", 14, .control)
        check("⌃E → goma", ctrl.instrumentoEfectivo == .goma)
        tecla("p", 35, .control)

        let g0 = ctrl.grosorActual
        tecla("]", 30)
        let g1 = ctrl.grosorActual
        tecla(",", 43)
        check("la rueda de la Huion sube con ] y baja con ,",
              g1 > g0 && ctrl.grosorActual == g0, "\(g0) → \(g1) → \(ctrl.grosorActual)")
        tecla(".", 47)
        check("y también con . (el otro mapeo del driver)", ctrl.grosorActual > g0)
        ctrl.ponerGrosor(g0)

        // ── la tira de grosores ────────────────────────────────────────────
        check("la tira nace cerrada", !ctrl.paleta.tira.estaAbierta)
        ctrl.paleta.tira.abrir(ancla: CGRect(x: pantalla.frame.midX, y: pantalla.frame.minY + 80,
                                             width: 48, height: 36))
        check("la tira abre", ctrl.paleta.tira.estaAbierta)
        ctrl.paleta.cerrarTira()
        ctrl.elegir(.goma)   // el bloque de arriba dejó el lápiz: se devuelve la goma

        if let e0 = evento(.leftMouseDown, base.x + 130, base.y + 90, 0.5, 1) {
            vista.mouseDown(with: e0)
        }
        if let e1 = evento(.leftMouseDragged, base.x + 130, base.y + 60, 0.5, 1.01) {
            vista.mouseDragged(with: e1)
        }
        if let e2 = evento(.leftMouseUp, base.x + 130, base.y + 60, 0.0, 1.02) {
            vista.mouseUp(with: e2)
        }
        check("la goma se llevó el trazo", ctrl.pizarra.trazos.isEmpty,
              "\(ctrl.pizarra.trazos.count) quedaron")
        ctrl.pizarra.deshacer()
        check("y deshacer lo devolvió", ctrl.pizarra.trazos.count == 1)

        ctrl.salir()
        check("al salir no queda tinta ni ventanas visibles",
              ctrl.pizarra.estaVacia && !ventanas.contains(where: \.isVisible))
        check("y la paleta se fue con él", !ctrl.paleta.estaVisible)
        check("la fusión de eventos sigue restaurada", NSEvent.isMouseCoalescingEnabled)

        print("")
        print(fallos == 0 ? "HUMO LIMPIO" : "\(fallos) FALLO(S) DE CABLEADO")
        return fallos == 0 ? 0 : 1
    }

    /// Área rellena del camino, contada a lo bruto sobre un bitmap. Sirve para
    /// comparar dos trazos entre sí, que es lo único que se le pide.
    private static func area(_ cam: CGPath?) -> Double {
        guard let cam else { return 0 }
        let caja = cam.boundingBoxOfPath.insetBy(dx: -4, dy: -4)
        let w = max(1, Int(caja.width)), h = max(1, Int(caja.height))
        guard w * h < 8_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: -caja.minX, y: -caja.minY)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.addPath(cam)
        ctx.fillPath(using: .winding)
        guard let d = ctx.data else { return 0 }
        let buf = d.bindMemory(to: UInt8.self, capacity: w * h)
        var n = 0.0
        for i in 0..<(w * h) { n += Double(buf[i]) / 255 }
        return n
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: la paleta, a PNG
// ════════════════════════════════════════════════════════════════════════════

extension PizarraTest {

    /// Render de la paleta a PNG, sin abrirla en pantalla. Una barra se juzga
    /// mirándola: "compila" no es "se lee de un vistazo".
    @MainActor
    static func paletaPNG(_ salida: String) -> Int32 {
        let ctrl = PizarraController()
        ctrl.silencioso = true
        let vista = PaletaVista()
        vista.ctrl = ctrl
        vista.frame = NSRect(origin: .zero, size: vista.tamanoNatural)

        // Tres estados en una hoja: lápiz morado fino, marcador ámbar gordo y
        // goma. Es donde se ve si la muestra de calibre y el activo se leen.
        let estados: [(String, () -> Void)] = [
            ("lápiz", { ctrl.elegir(.lapiz); ctrl.elegir(.morado) }),
            ("marcador", { ctrl.elegir(.marcador); ctrl.elegir(.ambar)
                           ctrl.elegir(.marcador); ctrl.moverGrosor(pasos: 2) }),
            ("goma", { ctrl.elegir(.goma) }),
        ]

        // Y la tira de cada instrumento debajo: es donde se ve si la escalera
        // se lee de un vistazo y si cada marca dice qué instrumento calibras.
        let tiras = Instrumento.allCases
        let vistaTira = TiraVista()
        vistaTira.ctrl = ctrl

        let w = Int(vista.bounds.width) + 40
        let h = (Int(vista.bounds.height) + 22) * (estados.count + tiras.count) + 22
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        // Fondo a media luz: la paleta vive sobre pantallas ajenas, no sobre
        // blanco ni sobre negro.
        ctx.setFillColor(CGColor(srgbRed: 0.33, green: 0.31, blue: 0.38, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        var y = h - Int(vista.bounds.height) - 22
        for (nombre, poner) in estados {
            poner()
            guard let rep = vista.bitmapImageRepForCachingDisplay(in: vista.bounds) else { continue }
            vista.cacheDisplay(in: vista.bounds, to: rep)
            if let img = rep.cgImage {
                ctx.draw(img, in: CGRect(x: 20, y: CGFloat(y), width: vista.bounds.width,
                                         height: vista.bounds.height))
            }
            print("  \(nombre): \(Int(vista.bounds.width))x\(Int(vista.bounds.height))")
            y -= Int(vista.bounds.height) + 22
        }

        for inst in tiras {
            ctrl.elegir(inst)
            vistaTira.frame = NSRect(origin: .zero, size: vistaTira.tamano)
            guard let rep = vistaTira.bitmapImageRepForCachingDisplay(in: vistaTira.bounds)
            else { continue }
            vistaTira.cacheDisplay(in: vistaTira.bounds, to: rep)
            if let img = rep.cgImage {
                ctx.draw(img, in: CGRect(x: 20, y: CGFloat(y), width: vistaTira.bounds.width,
                                         height: vistaTira.bounds.height))
            }
            print("  tira \(inst.nombre): \(inst.escalera.count) peldaños")
            y -= Int(vistaTira.bounds.height) + 22
        }

        guard let img = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
        else { return 1 }
        try? png.write(to: URL(fileURLWithPath: salida))
        print("paleta → \(salida)")
        return 0
    }
}
