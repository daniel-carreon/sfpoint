import AppKit

/// Vista transparente que pinta el laser. Trabaja en coordenadas GLOBALES de
/// pantalla y traslada su contexto, para que el laser y su estela crucen de un
/// monitor a otro sin costuras.
final class LaserOverlayView: NSView {
    weak var controller: LaserController?
    /// Origen global de la pantalla que cubre esta vista.
    var screenOrigin: CGPoint = .zero

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // jamas intercepta el raton
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctrl = controller, ctrl.state != .off,
              let color = ctrl.state.color,
              let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.saveGState()
        // global → local: el resto del dibujo piensa en coordenadas de pantalla
        ctx.translateBy(x: -screenOrigin.x, y: -screenOrigin.y)
        ctx.setShouldAntialias(true)

        LaserRenderer.drawLaser(in: ctx, pos: ctrl.pos, trail: ctrl.trail, color: color)

        let now = CACurrentMediaTime()
        for ripple in ctrl.ripples {
            let progress = CGFloat((now - ripple.t0) / Config.rippleDuration)
            if progress >= 0, progress < 1 {
                LaserRenderer.drawRipple(in: ctx, pos: ripple.pos,
                                         progress: progress, color: ripple.color)
            }
        }
        ctx.restoreGState()
    }
}

/// Panel transparente, click-through, que cubre exactamente una pantalla.
///
/// Tres invariantes que NO se pueden romper:
///  1. `ignoresMouseEvents = true` — el laser jamas bloquea el raton.
///  2. `.nonactivatingPanel` — jamas roba el foco de la app en la que trabajas.
///  3. `canJoinAllSpaces` — sigue visible al cambiar de escritorio o en pantalla completa.
final class LaserOverlayWindow: NSPanel {

    let overlayView = LaserOverlayView()

    init(screen: NSScreen, controller: LaserController) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        // Que no aparezca en el conmutador de ventanas ni robe teclado
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
        overlayView.autoresizingMask = [.width, .height]
        overlayView.controller = controller
        overlayView.screenOrigin = screen.frame.origin
        contentView = overlayView

        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Repinta SOLO el rectangulo sucio, en coordenadas globales.
    func setNeedsDisplay(globalRect: CGRect) {
        let local = globalRect.offsetBy(dx: -frame.origin.x, dy: -frame.origin.y)
        overlayView.setNeedsDisplay(local.insetBy(dx: -2, dy: -2))
    }

    func bringToFront() {
        orderFrontRegardless()
    }
}
