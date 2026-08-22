import AppKit

@main
struct SFPointApp {
    static func main() {
        // Modo headless de verificacion: renderiza a PNG y sale, sin abrir la app.
        let args = CommandLine.arguments
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
