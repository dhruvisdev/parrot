import AppKit
import SwiftUI

@MainActor final class OrbModel: ObservableObject {
    @Published var level: Float = 0
    @Published var caption = "Listening"
    @Published var text = ""
    @Published var processing = false
}

struct OrbView: View {
    @ObservedObject var model: OrbModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let level = CGFloat(min(max(model.level, 0), 1))
                let breath = reduceMotion ? 0 : sin(time * 2) * 0.8
                let size: CGFloat = 40 + (reduceMotion ? 0 : level * 6) + breath
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: size + 8, height: size + 8)
                        .blur(radius: 8)
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(red: 0.66, green: 0.85, blue: 0.83),
                                     Color(red: 0.19, green: 0.48, blue: 0.49),
                                     Color(red: 0.10, green: 0.19, blue: 0.24)],
                            center: .init(x: 0.3, y: 0.22), startRadius: 0, endRadius: size * 0.8))
                    Circle()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.75)
                    Ellipse()
                        .fill(.white.opacity(0.4))
                        .frame(width: 12, height: 6).blur(radius: 3)
                        .offset(x: -7, y: -11)
                    if model.processing {
                        Circle()
                            .trim(from: 0, to: 0.25)
                            .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .padding(-4)
                            .rotationEffect(.degrees(reduceMotion ? -90 : time * 120))
                    }
                }
                .frame(width: size, height: size)
                .frame(width: 64, height: 64)
            }
            .accessibilityHidden(true)
            VStack(spacing: 5) {
                Text(model.caption).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                if !model.text.isEmpty {
                    Text(model.text).font(.system(size: 14, weight: .medium)).lineLimit(3).multilineTextAlignment(.center)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(16).frame(width: 380, height: 210, alignment: .bottom)
        .preferredColorScheme(.dark)
    }
}

@MainActor final class OrbPanel {
    let model = OrbModel()
    private var panel: NSPanel?
    func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 210), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating; panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: OrbView(model: model))
            self.panel = panel
        }
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let rect = screen?.visibleFrame { panel?.setFrameOrigin(NSPoint(x: rect.midX - 190, y: rect.minY + 25)) }
        panel?.orderFrontRegardless()
    }
    func hide() {
        panel?.orderOut(nil)
        // Release the hosting view so TimelineView cannot continue rendering while idle.
        panel?.contentView = nil; panel = nil
    }
}
