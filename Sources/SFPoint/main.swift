import AppKit

@main
struct SFPointApp {
    static func main() {
        // Modo headless de verificacion: renderiza a PNG y sale, sin abrir la app.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--banco") {
            let dir = (i + 1 < args.count && !args[i+1].hasPrefix("--")) ? args[i+1] : "/tmp/sfpoint-banco"
            var color = "ambar"
            if let c = args.firstIndex(of: "--color"), c + 1 < args.count { color = args[c+1] }
            exit(TrailBench.run(dir: dir, colorName: color))
        }
        if let i = args.firstIndex(of: "--banco-tinta") {
            let dir = (i + 1 < args.count && !args[i+1].hasPrefix("--")) ? args[i+1] : "/tmp/sfpoint-banco-tinta"
            var ruta = PizarraTest.bancoPorDefecto
            if let r = args.firstIndex(of: "--json"), r + 1 < args.count { ruta = args[r+1] }
            exit(PizarraTest.banco(dir: dir, ruta: ruta))
        }
        // El chequeo mas barato contra la sordera silenciosa: TCC concedido o no.
        // Una app firmada ad-hoc pierde este permiso en cada rebuild y se ve
        // perfectamente viva mientras ningun atajo funciona.
        if args.contains("--permiso") {
            let ok = CGPreflightListenEventAccess()
            print("Monitorizacion de entrada: \(ok ? "CONCEDIDA" : "DENEGADA")")
            if !ok { print("reparar con:  tccutil reset ListenEvent \(Config.bundleID)") }
            exit(ok ? 0 : 2)
        }
        // Que clase de tap nos dejo crear macOS. Importa porque son DOS
        // permisos distintos: consumir teclas pide Accesibilidad; escucharlas,
        // Monitorizacion de entrada.
        if args.contains("--tap-test") {
            let h = HotkeyListener()
            let ok = h.start()
            print("tap creado:      \(ok ? "SI" : "NO")")
            print("puede consumir:  \(h.puedeConsumir ? "SI (⌥L no escribe ¬)" : "NO (solo escucha)")")
            print("vivo:            \(h.isRunning ? "SI" : "NO")")
            h.stop()
            exit(ok ? 0 : 1)
        }
        if let i = args.firstIndex(of: "--goma-png") {
            let out = (i + 1 < args.count && !args[i+1].hasPrefix("--")) ? args[i+1] : "/tmp/sfpoint-goma.png"
            exit(MainActor.assumeIsolated { PizarraTest.gomaPNG(out) })
        }
        if let i = args.firstIndex(of: "--paleta-png") {
            let out = (i + 1 < args.count && !args[i+1].hasPrefix("--")) ? args[i+1] : "/tmp/sfpoint-paleta.png"
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            exit(MainActor.assumeIsolated { PizarraTest.paletaPNG(out) })
        }
        if args.contains("--pizarra-humo") {
            // Necesita NSApp vivo (paneles, primer respondedor) pero NO activa la
            // app ni roba el foco: sigue siendo accessory.
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let codigo = MainActor.assumeIsolated { PizarraTest.humo() }
            exit(codigo)
        }
        if args.contains("--pizarra-test") {
            exit(MainActor.assumeIsolated { PizarraTest.modelo() })
        }
        if let i = args.firstIndex(of: "--selftest") {
            let out = (i + 1 < args.count && !args[i+1].hasPrefix("--")) ? args[i+1] : "/tmp/sfpoint-swift.png"
            var color = "ambar"
            if let c = args.firstIndex(of: "--color"), c + 1 < args.count { color = args[c+1] }
            exit(SelfTest.run(outputPath: out, colorName: color))
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Sin icono en el Dock: SFPoint vive en la barra de menu.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
