import AppKit
import Combine
import SwiftUI

struct AppearancePolicy {
    let glassEnabled: Bool
    let lowPowerMode: Bool
    let reduceTransparency: Bool
    let reduceMotion: Bool

    var effectiveGlass: Bool { glassEnabled && !lowPowerMode && !reduceTransparency }
    var animationsAllowed: Bool { !lowPowerMode && !reduceMotion }
}

/// Appearance changes are driven by preferences and system notifications, never a timer.
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()
    @Published var glassEnabled: Bool {
        didSet { defaults.set(glassEnabled, forKey: "LiquidGlassEnabled") }
    }
    @Published private(set) var lowPowerMode: Bool
    @Published private(set) var reduceTransparency: Bool
    @Published private(set) var reduceMotion: Bool
    private let defaults: UserDefaults
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var policy: AppearancePolicy {
        AppearancePolicy(glassEnabled: glassEnabled, lowPowerMode: lowPowerMode,
                         reduceTransparency: reduceTransparency, reduceMotion: reduceMotion)
    }
    var effectiveGlass: Bool { policy.effectiveGlass }
    var animationsAllowed: Bool { policy.animationsAllowed }
    var glassStatus: String? {
        guard glassEnabled else { return nil }
        if reduceTransparency { return "Glass paused: Reduce Transparency is on" }
        if lowPowerMode { return "Glass paused: Low Power Mode is on" }
        if #available(macOS 26.0, *) { return nil }
        return "Using frosted glass on this version of macOS"
    }

    init(defaults: UserDefaults = .standard, observeSystem: Bool = true) {
        self.defaults = defaults
        glassEnabled = defaults.bool(forKey: "LiquidGlassEnabled")
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard observeSystem else { return }
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.refreshSystemSettings()
        }
        observers.append((center, token))
    }

    func refreshSystemSettings() {
        let power = ProcessInfo.processInfo.isLowPowerModeEnabled
        let transparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let motion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if lowPowerMode != power { lowPowerMode = power }
        if reduceTransparency != transparency { reduceTransparency = transparency }
        if reduceMotion != motion { reduceMotion = motion }
    }

    deinit { observers.forEach { $0.0.removeObserver($0.1) } }
}

private struct NativeGlassSurface: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.contentView = NSView()
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        return effect
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            glass.tintColor = nil
        } else {
            view.layer?.cornerRadius = cornerRadius
            view.layer?.masksToBounds = true
        }
    }
}

private struct PaperSurface: ViewModifier {
    @ObservedObject private var appearance = AppearanceSettings.shared
    @Environment(\.colorScheme) private var scheme
    let color: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            if appearance.effectiveGlass {
                NativeGlassSurface(cornerRadius: cornerRadius)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(GlassStyle.canvas.opacity(scheme == .dark ? 0.86 : 0.72)))
                    .allowsHitTesting(false).accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius).fill(color)
            }
        }
        .transaction { if !appearance.animationsAllowed { $0.animation = nil } }
    }
}

extension View {
    /// Apply once at the root of each window/panel; inner surfaces should use tinted fills.
    func paperSurface(color: Color, cornerRadius: CGFloat = 0) -> some View {
        modifier(PaperSurface(color: color, cornerRadius: cornerRadius))
    }
}
