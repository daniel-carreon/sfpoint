import AppKit

/// Atajo global: ⌥P cicla el laser, Esc lo apaga.
///
/// Usa un CGEventTap de SOLO ESCUCHA (`.listenOnly`): jamas se traga la tecla,
/// asi que ⌥P sigue llegando a la app que este al frente. macOS lo protege tras
/// "Monitorizacion de entrada" (kTCCServiceListenEvent).
final class HotkeyListener {

    /// @Sendable: el tap corre fuera del hilo principal, asi que los
    /// callbacks se copian a una constante local antes de despacharlos —
    /// nunca se envia `self` a traves del limite de concurrencia.
    var onCycle: (@Sendable () -> Void)?
    var onOff: (@Sendable () -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Arranca (o reinicia) el tap. Es seguro llamarlo varias veces: asi se
    /// revive el atajo en el momento exacto en que el usuario concede el permiso.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)   // nunca consumimos la tecla
        }

        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false   // macOS nego el permiso: el llamador debe avisar
        }

        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    var isRunning: Bool {
        guard let t = tap else { return false }
        return CGEvent.tapIsEnabled(tap: t)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // Si macOS deshabilita el tap (timeout o entrada de usuario), revivirlo:
        // un tap apagado se ve identico a uno vivo, y la app quedaria sorda.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return
        }
        guard type == .keyDown else { return }

        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if code == Config.vkEsc {
            if let cb = onOff { DispatchQueue.main.async { cb() } }
            return
        }

        // ⌥P: Option SI, Command/Control NO (⌘P es imprimir, no es lo nuestro)
        let optionHeld = flags.contains(.maskAlternate)
        let blocked = flags.contains(.maskCommand) || flags.contains(.maskControl)
        if code == Config.vkP && optionHeld && !blocked {
            if let cb = onCycle { DispatchQueue.main.async { cb() } }
        }
    }
}

/// Monitorizacion de entrada (TCC).
///
/// POR QUE EXISTE ESTO: cuando falta el permiso — o peor, cuando su requisito
/// de firma guardado ya no coincide con la app tras un rebuild — el tap se
/// deniega EN SILENCIO. La app se ve viva y esta completamente sorda.
/// Aqui se comprueba antes, se avisa, y se ofrece la reparacion de un solo paso.
enum Permissions {
    static let settingsPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    /// Lanza el dialogo nativo. macOS lo muestra UNA sola vez por firma de app:
    /// si devuelve false sin UI, la app tiene que hablar por si misma.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    static func openSettingsPane() {
        if let url = URL(string: settingsPane) { NSWorkspace.shared.open(url) }
    }

    /// El comando exacto que limpia un registro TCC obsoleto de esta app.
    static var repairCommand: String { "tccutil reset ListenEvent \(Config.bundleID)" }
}
