import AppKit

/// Parrot's mark: a head in profile facing right, with sound waves leaving the beak.
/// Shared by the menu-bar item and scripts/icon, which renders the app icon.
/// Coordinates are a 100×100, y-down space.
enum ParrotMark {
    /// Reuse the bundled Finder icon in Settings, with the shared mark as a development fallback.
    static let appIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return menuBarImage(listening: false)
    }()

    /// The eye is a hole; fill with the even-odd rule. The neck runs past the bottom edge to be clipped.
    static func head() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 30, y: 130))
        path.addCurve(to: CGPoint(x: 18, y: 42), control1: CGPoint(x: 10, y: 100), control2: CGPoint(x: 8, y: 62))
        path.addCurve(to: CGPoint(x: 62, y: 18), control1: CGPoint(x: 26, y: 22), control2: CGPoint(x: 46, y: 12))
        path.addCurve(to: CGPoint(x: 77, y: 33), control1: CGPoint(x: 70, y: 21), control2: CGPoint(x: 75, y: 27))
        path.addCurve(to: CGPoint(x: 94, y: 58), control1: CGPoint(x: 88, y: 34), control2: CGPoint(x: 96, y: 44))
        path.addCurve(to: CGPoint(x: 86, y: 64), control1: CGPoint(x: 93, y: 63), control2: CGPoint(x: 89, y: 66))
        path.addCurve(to: CGPoint(x: 76, y: 51), control1: CGPoint(x: 87, y: 58), control2: CGPoint(x: 84, y: 52))
        path.addCurve(to: CGPoint(x: 74, y: 64), control1: CGPoint(x: 80, y: 56), control2: CGPoint(x: 80, y: 62))
        path.addCurve(to: CGPoint(x: 62, y: 60), control1: CGPoint(x: 68, y: 66), control2: CGPoint(x: 64, y: 62))
        path.addCurve(to: CGPoint(x: 64, y: 130), control1: CGPoint(x: 57, y: 78), control2: CGPoint(x: 56, y: 104))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: 55, y: 31, width: 10, height: 10))
        return path
    }
    /// Concentric arcs centred just past the beak tip, innermost first.
    static func waves(count: Int = 3) -> [CGPath] {
        (0..<count).map { index in
            let path = CGMutablePath()
            let radius = 15 + CGFloat(index) * 12.5
            path.addArc(center: CGPoint(x: 88, y: 52), radius: radius, startAngle: -.pi / 4.5, endAngle: .pi / 4.5, clockwise: false)
            return path
        }
    }

    /// Template image for the menu bar; waves appear only while listening.
    static func menuBarImage(listening: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.height / 100
            context.scaleBy(x: scale, y: scale)
            context.addPath(head()); context.fillPath(using: .evenOdd)
            if listening {
                context.setLineWidth(9); context.setLineCap(.round)
                for wave in waves(count: 2) { context.addPath(wave) }
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Parrot"
        return image
    }
}
