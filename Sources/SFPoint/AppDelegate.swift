import AppKit

/// SFPoint — puntero laser y pizarra para macOS.
///
/// ⌥P cicla el laser: apagado → ambar → morado → apagado.
/// ⌥L entra al modo lapiz (dibujar sobre CUALQUIER app, con presion e
/// inclinacion de la tableta); ⌥⇧L congela la tinta; Esc apaga lo que este
/// encendido.
///
/// LASER Y LAPIZ SON EXCLUYENTES, y no por comodidad: el laser oculta el cursor
/// y deja pasar el clic, el lapiz lo captura. Encender uno apaga el otro, y ese
/// cruce vive AQUI —el unico sitio que conoce a los dos— para que ninguno de los
/// dos controladores tenga que saber del otro. Vive en la barra de menu, no tiene icono en el Dock y
/// jamas roba el foco.
///
/// El icono de la barra refleja el estado Y sirve de superficie de control de
/// respaldo, para que la app siga siendo usable si macOS revoca el permiso.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: LaserController!
    private var pizarra: PizarraController!
    private let hotkey = HotkeyListener()
    private var lapizItem: NSMenuItem!
    private var congelarItem: NSMenuItem!
    private var statusItem: NSStatusItem!
    private var stateItems: [Config.LaserState: NSMenuItem] = [:]
    private var permItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var permissionOK = true
    private var watchdog: Timer?

    private var launchAgentPath: String {
        NSString(string: "~/Library/LaunchAgents/\(Config.bundleID).plist").expandingTildeInPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Solo barra de menu, sin icono en el Dock
        NSApp.setActivationPolicy(.accessory)

        controller = LaserController()
        controller.onStateChange = { [weak self] state in self?.reflect(state) }

        pizarra = PizarraController()
        pizarra.onModoChange = { [weak self] modo in self?.reflejarLapiz(modo) }

        buildMenuBar()
        wireHotkey()
        checkPermission(firstRun: true)

        // El instante en que el usuario concede el permiso, revivimos el atajo
        // sin obligarlo a buscar un boton de reinicio.
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPermission() }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t

        FileHandle.standardError.write(
            """
            SFPoint running
              ⌥P  laser: apagado → ambar → morado
              ⌥L  lapiz sobre cualquier app  ·  ⌥⇧L congela la tinta
              Esc apaga lo que este encendido

            """.data(using: .utf8)!)

        // --demo <segundos> [--color ambar|morado]: enciende el laser sin
        // depender del atajo, para poder verificarlo cuando TCC no coopera
        // (o simplemente para ver si dibuja, sin tocar el teclado).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--demo") {
            let secs = (i + 1 < args.count) ? (Double(args[i+1]) ?? 5.0) : 5.0
            var st: Config.LaserState = .ambar
            if let c = args.firstIndex(of: "--color"), c + 1 < args.count, args[c+1] == "morado" {
                st = .morado
            }
            controller.setState(st)
            FileHandle.standardError.write(
                "DEMO: laser \(st.label) por \(secs)s\n".data(using: .utf8)!)
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in
                self?.controller.setState(.off)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.stop()
        pizarra?.salir()
        controller.shutdown()
        watchdog?.invalidate()
    }

    // MARK: - Barra de menu

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.logoIcon()
        statusItem.button?.toolTip = "SFPoint — ⌥P para el laser"

        let menu = NSMenu()
        for state in Config.LaserState.allCases {
            let title = state == .off ? "\(state.label)   ⌥P" : state.label
            let item = NSMenuItem(title: title, action: #selector(pickState(_:)), keyEquivalent: "")
            item.target = self
            item.tag = state.rawValue
            item.state = (state == .off) ? .on : .off
            menu.addItem(item)
            stateItems[state] = item
        }

        menu.addItem(.separator())

        lapizItem = NSMenuItem(title: "Lapiz   ⌥L", action: #selector(toggleLapiz),
                               keyEquivalent: "")
        lapizItem.target = self
        menu.addItem(lapizItem)

        congelarItem = NSMenuItem(title: "Congelar tinta   ⌥⇧L", action: #selector(toggleCongelar),
                                  keyEquivalent: "")
        congelarItem.target = self
        congelarItem.isEnabled = false
        menu.addItem(congelarItem)

        let limpiar = NSMenuItem(title: "Limpiar pizarra", action: #selector(limpiarPizarra),
                                 keyEquivalent: "")
        limpiar.target = self
        menu.addItem(limpiar)

        menu.addItem(.separator())

        permItem = NSMenuItem(title: "⚠️  Falta permiso: Monitorizacion de entrada",
                              action: #selector(fixPermission), keyEquivalent: "")
        permItem.target = self
        permItem.isHidden = true
        menu.addItem(permItem)

        let restart = NSMenuItem(title: "Reiniciar SFPoint",
                                 action: #selector(restartApp), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        loginItem = NSMenuItem(title: "Iniciar con macOS",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = FileManager.default.fileExists(atPath: launchAgentPath) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func reflect(_ state: Config.LaserState) {
        for (s, item) in stateItems { item.state = (s == state) ? .on : .off }
        if let color = state.color {
            statusItem.button?.image = Self.dotIcon(color: color)
            statusItem.button?.toolTip = "SFPoint — laser \(state.label.lowercased())"
        } else {
            statusItem.button?.image = Self.logoIcon()
            statusItem.button?.toolTip = "SFPoint — ⌥P para el laser"
        }
    }

    // MARK: - Iconos

    /// Punto en el color activo del laser, para que el estado se vea de un vistazo.
    private static func dotIcon(color: NSColor) -> NSImage {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setShouldAntialias(true)
            let c = CGPoint(x: size / 2, y: size / 2)
            let (r, g, b) = color.rgb
            let stops: [(CGFloat, CGColor)] = [
                (0.0, RGBA(r, g, b, 120/255)),
                (1.0, RGBA(r, g, b, 0)),
            ]
            var locs = stops.map { $0.0 }
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: stops.map { $0.1 } as CFArray, locations: &locs) {
                ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                                       endCenter: c, endRadius: size * 0.5, options: [])
            }
            ctx.setFillColor(RGBA(r, g, b, 1))
            ctx.fillEllipse(in: CGRect(x: c.x - size * 0.23, y: c.y - size * 0.23,
                                       width: size * 0.46, height: size * 0.46))
        }
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    /// Icono en reposo: si hay logo horneado en el bundle se usa; si no, un
    /// punto de plantilla que se adapta al tema claro/oscuro de la barra.
    private static func logoIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "menubar", withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            // NO es template. Una template image descarta el color y pinta solo
            // la silueta del canal alpha; el arte anterior era el app icon, cuyo
            // alpha es un cuadrado 100% opaco, y por eso la barra mostraba un
            // cuadro blanco solido. El glifo va a color como en SFCast y SFlow.
            img.isTemplate = false
            return img
        }
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setShouldAntialias(true)
            ctx.setStrokeColor(RGBA(0, 0, 0, 1))
            ctx.setLineWidth(1.6)
            ctx.strokeEllipse(in: CGRect(x: size/2 - 5, y: size/2 - 5, width: 10, height: 10))
            ctx.setFillColor(RGBA(0, 0, 0, 1))
            ctx.fillEllipse(in: CGRect(x: size/2 - 2, y: size/2 - 2, width: 4, height: 4))
        }
        img.unlockFocus()
        img.isTemplate = true      // la barra lo tiñe segun el tema
        return img
    }

    // MARK: - Acciones

    @objc private func pickState(_ sender: NSMenuItem) {
        guard let s = Config.LaserState(rawValue: sender.tag) else { return }
        // Excluyentes tambien desde el menu, no solo desde el atajo: dos puertas
        // a lo mismo tienen que aplicar la misma regla o una de las dos miente.
        if s != .off && pizarra.modo != .apagado { pizarra.salir() }
        controller.setState(s)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: - Lapiz

    /// La regla de exclusion, en un solo sitio.
    @objc private func toggleLapiz() {
        if pizarra.modo == .apagado { controller.setState(.off) }
        pizarra.alternar()
    }

    @objc private func toggleCongelar() { pizarra.alternarCongelado() }

    @objc private func limpiarPizarra() { pizarra.limpiar() }

    private func reflejarLapiz(_ modo: PizarraController.Modo) {
        switch modo {
        case .apagado:
            lapizItem.state = .off
            lapizItem.title = "Lapiz   ⌥L"
            congelarItem.isEnabled = false
        case .dibujando:
            lapizItem.state = .on
            lapizItem.title = "Lapiz   ⌥L"
            congelarItem.isEnabled = true
        case .congelada:
            lapizItem.state = .mixed
            lapizItem.title = "Lapiz (tinta congelada)   ⌥L"
            congelarItem.isEnabled = true
        }
        // El icono de la barra tambien lo dice: una app sin retroalimentacion
        // visible es la que se queda muda cuando TCC le quita el atajo.
        if modo == .apagado {
            reflect(controller.state)
        } else {
            statusItem.button?.toolTip = modo == .dibujando
                ? "SFPoint — dibujando (⌥L sale, ⌥⇧L congela)"
                : "SFPoint — tinta congelada (⌥L sigue dibujando)"
        }
    }

    @objc private func restartApp() {
        let path = Config.appPath
        if FileManager.default.fileExists(atPath: path) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "sleep 1; open -n '\(path)'"]
            try? p.run()
        }
        NSApp.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = loginItem.state == .off
        let path = launchAgentPath
        if enabled {
            guard FileManager.default.fileExists(atPath: Config.appPath) else { return }
            let plist: [String: Any] = [
                "Label": Config.bundleID,
                "ProgramArguments": ["open", "-a", Config.appPath],
                "RunAtLoad": true,
            ]
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
        loginItem.state = enabled ? .on : .off
    }

    // MARK: - Permisos

    private func wireHotkey() {
        hotkey.onCycle = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Encender el laser saca del lapiz: son excluyentes.
                if self.pizarra.modo != .apagado { self.pizarra.salir() }
                self.controller.cycle()
            }
        }
        hotkey.onOff   = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Esc apaga PRIMERO lo que esta capturando la mano. Si apagara
                // siempre el laser, un Esc con la pizarra abierta no haria nada
                // visible y pareceria que la app no escucha.
                if self.pizarra.modo != .apagado { self.pizarra.salir(); return }
                self.controller.setState(.off)
            }
        }
        hotkey.onLapiz = { [weak self] in
            Task { @MainActor in self?.toggleLapiz() }
        }
        hotkey.onCongelar = { [weak self] in
            Task { @MainActor in self?.pizarra.alternarCongelado() }
        }
        _ = hotkey.start()
    }

    private func checkPermission(firstRun: Bool = false) {
        let ok = Permissions.hasInputMonitoring
        if ok == permissionOK && !firstRun { return }

        let wasBroken = !permissionOK
        permissionOK = ok
        permItem.isHidden = ok

        if ok {
            if wasBroken { _ = hotkey.start() }   // concedido en caliente: revivir el tap
            return
        }

        if firstRun {
            if Permissions.requestInputMonitoring() {
                permissionOK = true
                permItem.isHidden = true
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.warnMissingPermission()
            }
        }
    }

    @objc private func fixPermission() {
        Permissions.openSettingsPane()
        warnMissingPermission()
    }

    private func warnMissingPermission() {
        let box = NSAlert()
        box.alertStyle = .warning
        box.messageText = "SFPoint no puede escuchar ⌥P"
        box.informativeText = """
        macOS le esta negando el permiso de Monitorizacion de entrada.

        Mientras tanto el laser SI funciona desde el icono de la barra de menu.

        Para arreglarlo: activa SFPoint en Ajustes > Privacidad y Seguridad > \
        Monitorizacion de entrada. Si ya aparece activado, quitalo con el boton \
        menos y vuelve a agregarlo.

        Si el permiso quedo pegado despues de reconstruir la app, el registro \
        guardado ya no coincide con la firma. Se limpia con:

          \(Permissions.repairCommand)

        y despues se reinicia SFPoint.
        """
        box.addButton(withTitle: "Abrir Ajustes")
        box.addButton(withTitle: "Despues")
        if box.runModal() == .alertFirstButtonReturn {
            Permissions.openSettingsPane()
        }
    }
}
