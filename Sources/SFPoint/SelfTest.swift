import AppKit

/// Modo headless de verificacion: renderiza el laser y el ripple a un PNG
/// sin abrir una sola ventana. Existe para poder comparar el render de Swift
/// contra el de la version Python pixel a pixel — "compila" no es "se ve igual".
enum SelfTest {

    static let canvas = CGSize(width: 400, height: 300)

    /// Escena determinista: mismos puntos, mismo progreso, siempre.
    static let trail: [CGPoint] = (0..<18).map { i in
        CGPoint(x: 120 + CGFloat(i) * 6, y: 150 + sin(CGFloat(i) * 0.4) * 18)
    }
    static let dot = CGPoint(x: 228, y: 150)
    static let ripplePos = CGPoint(x: 120, y: 90)
    static let rippleProgress: CGFloat = 0.35

    static func run(outputPath: String, colorName: String) -> Int32 {
        let color: NSColor = (colorName == "morado") ? Config.morado : Config.ambar

        guard let ctx = CGContext(
            data: nil,
            width: Int(canvas.width), height: Int(canvas.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            FileHandle.standardError.write("selftest: no pude crear el contexto\n".data(using: .utf8)!)
            return 1
        }

        // Fondo negro opaco: el laser se dibuja sobre transparencia en la app
        // real, pero para comparar necesitamos un fondo identico en ambos motores.
        ctx.setFillColor(RGBA(0, 0, 0, 1))
        ctx.fill(CGRect(origin: .zero, size: canvas))
        ctx.setShouldAntialias(true)

        LaserRenderer.drawLaser(in: ctx, pos: dot, trail: trail, color: color)
        LaserRenderer.drawRipple(in: ctx, pos: ripplePos,
                                 progress: rippleProgress, color: Config.opposite(of: color))

        guard let image = ctx.makeImage() else { return 1 }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        do {
            try data.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            FileHandle.standardError.write("selftest: no pude escribir \(outputPath)\n".data(using: .utf8)!)
            return 1
        }

        // Metricas que un humano puede leer y un script puede comparar
        let stats = measure(image: image)
        print("=== SFPoint selftest (\(colorName)) ===")
        print("lienzo:            \(Int(canvas.width))x\(Int(canvas.height))")
        print("pixeles no negros: \(stats.lit)")
        print("centroide:         (\(String(format: "%.1f", stats.cx)), \(String(format: "%.1f", stats.cy)))")
        print("luminancia media:  \(String(format: "%.4f", stats.meanLuma))")
        print("pico:              \(String(format: "%.4f", stats.peak))")
        print("salida:            \(outputPath)")
        return 0
    }

    private static func measure(image: CGImage) -> (lit: Int, cx: Double, cy: Double,
                                                    meanLuma: Double, peak: Double) {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (0, 0, 0, 0, 0) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var lit = 0, sumX = 0.0, sumY = 0.0, sumL = 0.0, peak = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Double(buf[i]) / 255, g = Double(buf[i+1]) / 255, b = Double(buf[i+2]) / 255
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                sumL += luma
                if luma > peak { peak = luma }
                if luma > 0.02 {
                    lit += 1
                    sumX += Double(x); sumY += Double(y)
                }
            }
        }
        let n = Double(max(lit, 1))
        return (lit, sumX / n, sumY / n, sumL / Double(w * h), peak)
    }
}
