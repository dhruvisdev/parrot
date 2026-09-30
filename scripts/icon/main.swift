// Renders Parrot's app icon into an .iconset. Run through scripts/make-icon.sh.
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

/// Draws on a 1024 canvas, y-down, following the macOS icon grid (824pt body, 100pt margin).
func draw(_ context: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: color(0x000000, 0.35))
    context.addPath(shape); context.setFillColor(color(0x1A1446)); context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape); context.clip()
    context.drawLinearGradient(gradient([color(0x4B3BC4), color(0x2A1F7A), color(0x120D34)]),
                               start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.drawRadialGradient(gradient([color(0x39E0F0, 0.55), color(0x39E0F0, 0)]),
                               startCenter: CGPoint(x: 430, y: 470), startRadius: 0, endCenter: CGPoint(x: 430, y: 470), endRadius: 420, options: [])

    // Shifted left so the waves have room; the neck runs off the bottom and is clipped by the body.
    context.translateBy(x: 150, y: 250)
    context.scaleBy(x: 5.4, y: 5.4)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 5, color: color(0x07051A, 0.5))
    context.addPath(ParrotMark.head()); context.setFillColor(color(0xFFFFFF)); context.fillPath(using: .evenOdd)
    context.restoreGState()
    context.saveGState()
    context.addPath(ParrotMark.head()); context.clip(using: .evenOdd)
    context.drawLinearGradient(gradient([color(0xFFFFFF), color(0xC9F6FB), color(0x6FD8EA)]),
                               start: CGPoint(x: 30, y: 15), end: CGPoint(x: 70, y: 95), options: [])
    context.restoreGState()

    context.setLineCap(.round); context.setLineWidth(7.5)
    for (index, wave) in ParrotMark.waves().enumerated() {
        context.addPath(wave)
        context.setStrokeColor(color(0x7CF3D8, 1 - CGFloat(index) * 0.28))
        context.strokePath()
    }
    context.restoreGState()
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let pixels = points * scale
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(pixels)); context.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
        draw(context)
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let data = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent(name))
    }
}
