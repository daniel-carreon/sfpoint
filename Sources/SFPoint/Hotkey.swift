import AppKit

/// Atajos globales: ⌥P cicla el laser, ⌥L entra/sale del modo lapiz,
/// ⌥⇧L congela la tinta, Esc apaga lo que este encendido.
///
/// El tap DEJA PASAR TODO menos ⌥L y ⌥⇧L. macOS lo protege tras
/// "Monitorizacion de entrada" (kTCCServiceListenEvent).
///
/// ⚠️ ENMIENDA AL INVARIANTE 3 (29 ago 2026, al nacer el modo lapiz). El tap era
/// `.listenOnly` para no robarle NUNCA una tecla a la app de enfrente, y esa
/// sigue siendo la regla: ⌥P, Esc y absolutamente todo lo demas se reenvian
/// intactos. La excepcion es ⌥L, y tiene una razon medible: en el teclado de
/// Daniel ⌥L ESCRIBE "¬". Con el tap sordo, abrir la pizarra encima de un editor
/// le metia un caracter basura en el texto cada vez. Un atajo que ensucia el
/// documento que vas a anotar no es un atajo.
///
/// Se traga EXACTAMENTE ⌥L y ⌥⇧L (sin ⌘ ni ⌃) y nada mas. Si el tap muriera, el
/// unico coste es que el atajo deja de responder — la segunda superficie (el
/// menu de la barra) sigue abriendo el lapiz.
final class HotkeyListener {

    /// @Sendable: el tap corre fuera del hilo principal, asi que los
    /// callbacks se copian a una constante local antes de despacharlos —
    /// nunca se envia `self` a traves del limite de concurrencia.
    var onCycle: (@Sendable () -> Void)?
    var onOff: (@Sendable () -> Void)?
    /// ⌥L — el modo lapiz (pizarra sobre cualquier app).
    var onLapiz: (@Sendable () -> Void)?
    /// ⌥⇧L — congelar la tinta y devolver el clic a las apps.
    var onCongelar: (@Sendable () -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// `true` si macOS nos dejo crear un tap que PUEDE consumir teclas. Si no,
    /// se cae a solo-escucha y el atajo sigue funcionando (⌥L abre la pizarra),
    /// solo que ademas escribe su caracter en la app de enfrente.
    private(set) var puedeConsumir = false

    /// Arranca (o reinicia) el tap. Es seguro llamarlo varias veces: asi se
    /// revive el atajo en el momento exacto en que el usuario concede el permiso.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()
            // La decision de tragarse o no la tecla se toma AQUI y en sincrono:
            // el callback del tap no puede esperar al hilo principal sin que
            // macOS lo mate por lento.
            if me.handle(type: type, event: event) { return nil }
            return Unmanaged.passUnretained(event)
        }

        /*
         * DOS INTENTOS, y el segundo no es paranoia: un tap que CONSUME teclas
         * (`.defaultTap`) exige Accesibilidad, mientras que uno de solo escucha
         * exige Monitorizacion de entrada. Son permisos DISTINTOS. Pedir el
         * primero y rendirse si falta dejaria la app entera sorda —incluido ⌥P,
         * que lleva meses funcionando— por una comodidad del lapiz.
         *
         * Asi que: se intenta el que puede tragarse ⌥L y, si macOS lo niega, se
         * cae al de siempre. Lo unico que se pierde es que ⌥L escriba "¬" en la
         * app de enfrente; todo lo demas sigue igual. Degradar, no morir.
         */
        var creado = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        puedeConsumir = creado != nil
        if creado == nil {
            creado = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        }
        guard let t = creado else {
            return false   // macOS nego los dos: el llamador debe avisar
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

    /// Devuelve `true` SOLO si la tecla se consume (⌥L / ⌥⇧L).
    @discardableResult
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // Si macOS deshabilita el tap (timeout o entrada de usuario), revivirlo:
        // un tap apagado se ve identico a uno vivo, y la app quedaria sorda.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return false
        }
        guard type == .keyDown else { return false }

        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if code == Config.vkEsc {
            if let cb = onOff { DispatchQueue.main.async { cb() } }
            return false      // Esc es de todos: jamas se consume
        }

        // ⌥P: Option SI, Command/Control NO (⌘P es imprimir, no es lo nuestro)
        let optionHeld = flags.contains(.maskAlternate)
        let blocked = flags.contains(.maskCommand) || flags.contains(.maskControl)
        if code == Config.vkP && optionHeld && !blocked {
            if let cb = onCycle { DispatchQueue.main.async { cb() } }
            return false      // ⌥P sigue llegando a la app de enfrente
        }

        // ⌥L: el lapiz. Con ⇧, congela. Mismo criterio que ⌥P: Option SI,
        // Command/Control NO — ⌘L es la barra de direcciones de medio mundo.
        if code == Config.vkL && optionHeld && !blocked {
            let cb = flags.contains(.maskShift) ? onCongelar : onLapiz
            if let cb { DispatchQueue.main.async { cb() } }
            return puedeConsumir   // la unica que se traga: si no, escribe "¬"
        }
        return false
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
