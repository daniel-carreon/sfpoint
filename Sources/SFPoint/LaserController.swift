import AppKit

struct Ripple {
    let pos: CGPoint
    let t0: CFTimeInterval
    let color: NSColor
}

/// Dueño del estado del laser; maneja los overlays, la estela y el cursor.
///
/// Contrato de eficiencia (heredado de la version Python y respetado aqui):
///   laser APAGADO → overlays ocultos, cero timers, cero listeners, ~0% CPU
///   laser ENCENDIDO → un timer a 60fps que repinta SOLO el rectangulo sucio
@MainActor
final class LaserController {

    private(set) var state: Config.LaserState = .off
    private(set) var pos: CGPoint?
    private(set) var trail: [CGPoint] = []
    private(set) var ripples: [Ripple] = []

    private var windows: [LaserOverlayWindow] = []
    private var timer: Timer?
    private var prevDirty: CGRect?
    private var clickMonitor: Any?

    /// Contador EXACTO de ocultamientos del cursor. Si esto se desbalancea, el
    /// usuario se queda sin cursor en todo el sistema y no hay como recuperarlo
    /// salvo reiniciando. Por eso se cuenta cada hide y se deshacen todos.
    private var cursorHides = 0

    var onStateChange: ((Config.LaserState) -> Void)?

    init() {
        buildWindows()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindows() }
        }
    }

    // MARK: - Overlays

    private func buildWindows() {
        windows = NSScreen.screens.map { LaserOverlayWindow(screen: $0, controller: self) }
    }

    private func rebuildWindows() {
        let wasOn = state != .off
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        buildWindows()
        if wasOn { showWindows() }
    }

    private func showWindows() {
        windows.forEach { $0.bringToFront() }
    }

    private func hideWindows() {
        windows.forEach { $0.orderOut(nil) }
    }

    // MARK: - API publica

    func cycle() { setState(state.next) }

    func setState(_ new: Config.LaserState) {
        guard new != state else { return }
        state = new
        onStateChange?(new)

        guard new != .off else {
            timer?.invalidate(); timer = nil
            stopClickMonitor()
            restoreCursor()
            pos = nil
            trail.removeAll()
            ripples.removeAll()
            prevDirty = nil
            hideWindows()
            return
        }

        trail.removeAll()
        pos = nil
        showWindows()
        startClickMonitor()
        hideCursor()

        let t = Timer(timeInterval: 1.0 / Config.fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common: la estela sigue viva mientras hay un menu abierto o se arrastra
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    // MARK: - Frame

    private func tick() {
        // El window server vuelve a mostrar el cursor cada vez que el foco se
        // mueve, asi que lo re-ocultamos en cada frame y contamos cada vez.
        hideCursor()

        let p = NSEvent.mouseLocation
        if pos == nil || abs(p.x - pos!.x) > 0.01 || abs(p.y - pos!.y) > 0.01 {
            pos = p
            trail.append(p)
            if trail.count > Config.trailLength {
                trail.removeFirst(trail.count - Config.trailLength)
            }
        } else if !trail.isEmpty {
            // El cursor se detuvo: la estela se consume hacia el punto
            trail.removeFirst()
        }

        if !ripples.isEmpty {
            let now = CACurrentMediaTime()
            ripples.removeAll { now - $0.t0 >= Config.rippleDuration }
        }

        repaintDirty()
    }

    private func repaintDirty() {
        let current = dirtyGlobalRect()
        if current == nil && prevDirty == nil { return }
        let region: CGRect
        switch (current, prevDirty) {
        case let (c?, p?): region = c.union(p)
        case let (c?, nil): region = c
        case let (nil, p?): region = p
        default: return
        }
        prevDirty = current
        for w in windows where w.isVisible {
            w.setNeedsDisplay(globalRect: region)
        }
    }

    private func dirtyGlobalRect() -> CGRect? {
        var rect: CGRect?
        var points = trail
        if let p = pos { points.append(p) }
        if !points.isEmpty {
            let xs = points.map(\.x), ys = points.map(\.y)
            rect = CGRect(x: xs.min()! - Config.laserPad,
                          y: ys.min()! - Config.laserPad,
                          width: (xs.max()! - xs.min()!) + Config.laserPad * 2,
                          height: (ys.max()! - ys.min()!) + Config.laserPad * 2)
        }
        for r in ripples {
            let rr = CGRect(x: r.pos.x - Config.ripplePad, y: r.pos.y - Config.ripplePad,
                            width: Config.ripplePad * 2, height: Config.ripplePad * 2)
            rect = rect?.union(rr) ?? rr
        }
        return rect
    }

    // MARK: - Clics (ripple en el color opuesto)

    private func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            Task { @MainActor in self?.addRipple(at: NSEvent.mouseLocation) }
            _ = event
        }
    }

    private func stopClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    private func addRipple(at p: CGPoint) {
        guard state != .off, let c = state.color else { return }
        ripples.append(Ripple(pos: p, t0: CACurrentMediaTime(), color: Config.opposite(of: c)))
    }

    // MARK: - Cursor (ocultar/mostrar BALANCEADO)

    private func hideCursor() {
        CGDisplayHideCursor(CGMainDisplayID())
        cursorHides += 1
    }

    /// Deshace TODOS los ocultamientos, con margen. Un contador desbalanceado
    /// deja al usuario sin cursor en todo el sistema.
    private func restoreCursor() {
        guard cursorHides > 0 else { return }
        for _ in 0..<(cursorHides + 8) { CGDisplayShowCursor(CGMainDisplayID()) }
        cursorHides = 0
    }

    // MARK: - Apagado

    /// SIEMPRE llamar antes de salir: una app que muere con el cursor oculto
    /// se lleva el cursor del usuario con ella.
    func shutdown() {
        timer?.invalidate(); timer = nil
        stopClickMonitor()
        restoreCursor()
    }
}
