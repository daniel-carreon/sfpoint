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

// MARK: - Banco de la estela

/// Una estela no se juzga con adjetivos. El banco congela escenas deterministas
/// (la misma estela a tres velocidades) y las pinta con los tres motores en el
/// MISMO rasterizador, mismo fondo, mismo antialiasing: si cada motor pintara en
/// su propia pila, el A/B mediria el rasterizador tanto como el motor.
///
///   ./.build/release/SFPoint --banco /tmp/banco
enum TrailBench {

    /// Separacion entre muestras = pixeles por frame a 60 fps. 4 = cursor casi
    /// quieto · 12 = movimiento normal · 30 = barrido rapido de pantalla.
    static let escenas: [(nombre: String, paso: CGFloat)] = [
        ("lento", 4), ("normal", 12), ("rapido", 30),
    ]
    static let motores: [(String, LaserRenderer.TrailStyle)] = [
        ("contorno", .contorno), ("segmentos-butt", .segmentosButt), ("segmentos-round", .segmentosRound),
    ]
    static let lienzo = CGSize(width: 640, height: 200)

    static func trail(paso: CGFloat) -> [CGPoint] {
        (0..<Config.trailLength).map { i in
            CGPoint(x: 50 + CGFloat(i) * paso, y: 100 + sin(CGFloat(i) * 0.4) * 18)
        }
    }

    static func run(dir: String, colorName: String) -> Int32 {
        let color: NSColor = (colorName == "morado") ? Config.morado : Config.ambar
        try? FileManager.default.createDirectory(atPath: dir,
                                                 withIntermediateDirectories: true)
        var hoja: [CGImage] = []
        print("=== banco de la estela (\(colorName)) ===")
        func pad(_ s: String, _ n: Int) -> String {
            s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
        }
        print(pad("motor", 17) + pad("escena", 9) + "  pixeles   luma media   ms/frame")

        for (mNombre, style) in motores {
            for (eNombre, paso) in escenas {
                let t = trail(paso: paso)
                guard let ctx = bitmap() else { return 1 }
                ctx.setFillColor(RGBA(0, 0, 0, 1))
                ctx.fill(CGRect(origin: .zero, size: lienzo))
                ctx.setShouldAntialias(true)
                LaserRenderer.drawLaser(in: ctx, pos: t.last, trail: t, color: color, style: style)
                guard let img = ctx.makeImage() else { return 1 }
                hoja.append(img)

                let path = "\(dir)/\(mNombre)-\(eNombre).png"
                if let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
                let s = stats(img)
                let ms = cronometra(style: style, trail: t, color: color)
                print(pad(mNombre, 17) + pad(eNombre, 9)
                      + String(format: "%9d %12.5f %10.3f", s.lit, s.meanLuma, ms))
            }
        }

        // Hoja de contacto: los 9 renders apilados, para mirarlos de un golpe.
        let W = Int(lienzo.width), H = Int(lienzo.height)
        if let sheet = CGContext(data: nil, width: W, height: H * hoja.count,
                                 bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            for (i, img) in hoja.enumerated() {
                // Se apilan en el orden impreso; la fila 0 queda ARRIBA.
                let y = H * (hoja.count - 1 - i)
                sheet.draw(img, in: CGRect(x: 0, y: y, width: W, height: H))
            }
            if let out = sheet.makeImage(),
               let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "\(dir)/hoja.png"))
                print("hoja de contacto:  \(dir)/hoja.png  (orden = el de la tabla)")
            }
        }
        return 0
    }

    private static func bitmap() -> CGContext? {
        CGContext(data: nil, width: Int(lienzo.width), height: Int(lienzo.height),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Coste real por frame: lo que decide si la estela cabe en 16.6 ms.
    private static func cronometra(style: LaserRenderer.TrailStyle,
                                   trail: [CGPoint], color: NSColor) -> Double {
        guard let ctx = bitmap() else { return 0 }
        ctx.setShouldAntialias(true)
        let reps = 300
        for _ in 0..<20 { LaserRenderer.drawLaser(in: ctx, pos: trail.last, trail: trail, color: color, style: style) }
        let t0 = CACurrentMediaTime()
        for _ in 0..<reps {
            LaserRenderer.drawLaser(in: ctx, pos: trail.last, trail: trail, color: color, style: style)
        }
        return (CACurrentMediaTime() - t0) * 1000 / Double(reps)
    }

    private static func stats(_ image: CGImage) -> (lit: Int, meanLuma: Double) {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (0, 0) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lit = 0, sum = 0.0
        for i in stride(from: 0, to: buf.count, by: 4) {
            let l = 0.2126 * Double(buf[i]) / 255 + 0.7152 * Double(buf[i+1]) / 255
                  + 0.0722 * Double(buf[i+2]) / 255
            sum += l
            if l > 0.02 { lit += 1 }
        }
        return (lit, sum / Double(w * h))
    }
}
