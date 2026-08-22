import AppKit

/// Configuracion de SFPoint. Los numeros son los MISMOS que la version Python:
/// esta app se reescribio en Swift sin cambiar una sola constante visual, para
/// que el laser se vea identico al que Daniel ya conocia.
enum Config {

    // MARK: - Colores de marca
    /// #F59E0B
    static let ambar  = NSColor(srgbRed: 245/255, green: 158/255, blue: 11/255, alpha: 1)
    /// #8C27F1
    static let morado = NSColor(srgbRed: 140/255, green:  39/255, blue: 241/255, alpha: 1)

    // MARK: - Estados (⌥P cicla entre ellos)
    enum LaserState: Int, CaseIterable {
        case off = 0, ambar = 1, morado = 2

        var color: NSColor? {
            switch self {
            case .off:    return nil
            case .ambar:  return Config.ambar
            case .morado: return Config.morado
            }
        }
        var label: String {
            switch self {
            case .off: return "Apagado"
            case .ambar: return "Ambar"
            case .morado: return "Morado"
            }
        }
        /// off → ambar → morado → off
        var next: LaserState {
            switch self {
            case .off: return .ambar
            case .ambar: return .morado
            case .morado: return .off
            }
        }
    }

    // MARK: - Geometria del laser
    static let dotRadius: CGFloat   = 7.5
    static let glowRadius: CGFloat  = 21.0
    static let trailLength          = 18

    // MARK: - Ripple (onda de choque del clic, en el color OPUESTO)
    static let rippleMaxRadius: CGFloat = 20.0
    static let rippleDuration: TimeInterval = 0.55

    // MARK: - Render
    static let fps: Double = 60

    /// Margenes para calcular el rectangulo sucio (en sync con el dibujo).
    static let laserPad: CGFloat  = glowRadius * 2.5 + 4.0
    static let ripplePad: CGFloat = rippleMaxRadius * 1.6 + 10.0

    // MARK: - Atajo
    /// Codigo de tecla virtual de "p" en macOS.
    static let vkP: CGKeyCode = 35
    static let vkEsc: CGKeyCode = 53

    // MARK: - Identidad
    static let bundleID = "so.saasfactory.sfpoint"
    static let appPath  = "/Applications/SFPoint.app"

    /// El ripple siempre usa el color de marca contrario al laser activo.
    static func opposite(of color: NSColor) -> NSColor {
        color.isEqualRGB(to: ambar) ? morado : ambar
    }
}

extension NSColor {
    func isEqualRGB(to other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        guard let c = usingColorSpace(.sRGB) else { return (0, 0, 0) }
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }
}
