import SwiftUI

private func adaptive(_ light: Int, _ dark: Int) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let code = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(cgColor: PaperArt.color(code))!
    })
}

enum GlassStyle {
    static let windowCornerRadius: CGFloat = 14
    static let cardCornerRadius: CGFloat = 16
    static let text = adaptive(0x20232C, 0xF3F5FB)
    static let secondary = adaptive(0x565E6E, 0xBBC1D0)
    static let faint = adaptive(0x697386, 0x959FB4)
    static let canvas = adaptive(0xF1F3F9, 0x11151D)
    static let chromeFill = adaptive(0xE6EAF5, 0x191E2A)
    static let controlFill = adaptive(0xFFFFFF, 0x303747).opacity(0.72)
    static let cardFill = adaptive(0xFFFFFF, 0x2A303E).opacity(0.80)
    static let line = adaptive(0x9BA5B9, 0x8694B1).opacity(0.23)
    static let selected = adaptive(0x8178EC, 0x9B9BF9).opacity(0.18)
    static let accent = adaptive(0x5D55CE, 0xADAEFF)
    static let actionFill = adaptive(0x625CE0, 0x979BF0)
    static let onAccent = adaptive(0xFFFFFF, 0x171B30)
}

enum Ink {
    private static var glass: Bool { AppearanceSettings.shared.effectiveGlass }
    static var text: Color { glass ? GlassStyle.text : adaptive(0x2E352D, 0xEFF0E7) }
    static var secondary: Color { glass ? GlassStyle.secondary : adaptive(0x586152, 0xC1C8B9) }
    static var faint: Color { glass ? GlassStyle.faint : adaptive(0x696F62, 0xAAB39F) }
    static var canvas: Color { glass ? GlassStyle.canvas : adaptive(0xFAFAF6, 0x262923) }
    static var sidebar: Color { glass ? GlassStyle.chromeFill : adaptive(0xEFF0E8, 0x1D211C) }
    static var surface: Color { glass ? GlassStyle.controlFill : adaptive(0xFFFFFC, 0x30352D) }
    static var line: Color { glass ? GlassStyle.line : adaptive(0xDADCD2, 0x43493D) }
    static var selected: Color { glass ? GlassStyle.selected : adaptive(0xDCE4D5, 0x354431) }
    static var accent: Color { glass ? GlassStyle.accent : adaptive(0x354D39, 0xC5DAB4) }
    static var onAccent: Color { glass ? GlassStyle.onAccent : adaptive(0xFFFFF6, 0x23351E) }
    static var greenDot: Color { glass ? adaptive(0x2C8769, 0x7FCEB0) : adaptive(0x55774E, 0xA3C391) }
    static var warning: Color { glass ? adaptive(0x9C5A2C, 0xF3BE87) : adaptive(0x98522C, 0xF0BA8C) }
}

extension PaperColor {
    var glassAccent: Color {
        switch self {
        case .butter: return adaptive(0xB78526, 0xE6BF72)
        case .sage: return adaptive(0x408978, 0x80C8B5)
        case .rose: return adaptive(0xBB6B83, 0xE5A3B7)
        case .blue: return adaptive(0x5789BF, 0x91BCE9)
        case .lilac: return adaptive(0x8870C5, 0xC0ACEF)
        }
    }
    var paper: Color {
        switch self {
        case .butter: return adaptive(0xF9EAB0, 0x49432E)
        case .sage: return adaptive(0xE0EACF, 0x344331)
        case .rose: return adaptive(0xF7DDD2, 0x4D3833)
        case .blue: return adaptive(0xDCE8F0, 0x303F4A)
        case .lilac: return adaptive(0xEAE1F0, 0x42394B)
        }
    }
    var fold: Color {
        switch self {
        case .butter: return adaptive(0xE8CC76, 0x786B44)
        case .sage: return adaptive(0xBECFA9, 0x536A49)
        case .rose: return adaptive(0xE4B5A1, 0x78554D)
        case .blue: return adaptive(0xB4CCDC, 0x506776)
        case .lilac: return adaptive(0xD0BBDD, 0x685474)
        }
    }
    var marker: Color {
        switch self {
        case .butter: return adaptive(0xB68A33, 0xDDC270)
        case .sage: return adaptive(0x66844F, 0xA7BD83)
        case .rose: return adaptive(0xBA735F, 0xD6A092)
        case .blue: return adaptive(0x6B8AA1, 0x93B3CA)
        case .lilac: return adaptive(0x9676AA, 0xBA9DCC)
        }
    }
}

struct PaperShape: Shape {
    let fold: CGFloat = 19
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r: CGFloat = 9
        return Path { p in
            p.move(to: CGPoint(x: r, y: 0))
            p.addLine(to: CGPoint(x: w-r, y: 0))
            p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w, y: h-fold))
            p.addLine(to: CGPoint(x: w-fold, y: h))
            p.addLine(to: CGPoint(x: r, y: h))
            p.addQuadCurve(to: CGPoint(x: 0, y: h-r), control: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: r))
            p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
            p.closeSubpath()
        }
    }
}

struct PaperFold: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX+4, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY+4), control: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

struct Eyebrow: View {
    let text: String
    @ObservedObject private var appearance = AppearanceSettings.shared
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold))
            .tracking(1.3).foregroundStyle(Ink.faint)
    }
}

struct ActionStyle: ButtonStyle {
    @ObservedObject private var appearance = AppearanceSettings.shared
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).frame(height: 34)
            .foregroundStyle(Ink.onAccent)
            .background(RoundedRectangle(cornerRadius: appearance.effectiveGlass ? 10 : 8, style: .continuous)
                .fill(appearance.effectiveGlass ? GlassStyle.actionFill : Ink.accent))
            .overlay {
                if appearance.effectiveGlass {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                }
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(Rectangle())
    }
}

enum NoteContentStyle {
    static func fontSize(glass: Bool) -> CGFloat { glass ? 14 : 13 }
    static let rowSpacing: CGFloat = 3
}

/// The same first-line alignment and editor styling on the board and desktop.
struct ChecklistRow<Field: View>: View {
    let label: String
    let complete: () -> Void
    @ViewBuilder let field: Field
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TaskCheck(label: label, action: complete)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4.5 }
            field.textFieldStyle(.plain)
                .font(.system(size: NoteContentStyle.fontSize(glass: appearance.effectiveGlass)))
                .foregroundStyle(Ink.text)
                .lineLimit(1...12).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TaskDraftRow<Field: View>: View {
    let draft: String
    let commit: () -> Void
    @ViewBuilder let field: Field
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                .frame(width: 21).foregroundStyle(Ink.secondary)
            field.legiblePrompt("Add a task…", visible: draft.isEmpty)
                .textFieldStyle(.plain)
                .font(.system(size: NoteContentStyle.fontSize(glass: appearance.effectiveGlass)))
                .foregroundStyle(Ink.text)
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: commit) {
                    Image(systemName: "return").font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 19)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Ink.text.opacity(0.09)))
                }.buttonStyle(.plain).accessibilityLabel("Add task").help("Add task (Return)")
            }
        }.frame(minHeight: 25)
    }
}

struct TaskCheck: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false
    @ObservedObject private var appearance = AppearanceSettings.shared
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Ink.secondary.opacity(0.77), lineWidth: 1.35)
                    .frame(width: 15, height: 15)
                if hovering {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                }
            }.frame(width: 21, height: 23).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Ink.secondary)
        .onHover { hovering = $0 }
        .accessibilityLabel("Complete \(label)")
        .help("Complete task and move it to the archive")
    }
}

struct CountBadge: View {
    let count: Int
    @ObservedObject private var appearance = AppearanceSettings.shared
    var body: some View {
        Text("\(count)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
            .foregroundStyle(Ink.secondary).padding(.horizontal, 6).frame(minWidth: 21, minHeight: 17)
            .background(Capsule().fill(Ink.text.opacity(0.065)))
    }
}

/// Lightweight glass styling for content cards. Native material is applied only at the window root.
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = GlassStyle.cardCornerRadius
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(GlassStyle.cardFill)
            .overlay(shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(scheme == .dark ? 0.18 : 0.95), .white.opacity(scheme == .dark ? 0.035 : 0.24)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
            .overlay(shape.strokeBorder(GlassStyle.line.opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.045), radius: 9, x: 0, y: 4)
    }
}

func plural(_ count: Int, _ one: String, _ many: String) -> String {
    "\(count) \(count == 1 ? one : many)"
}

extension View {
    func glassCard(cornerRadius: CGFloat = GlassStyle.cardCornerRadius) -> some View {
        background(GlassCardBackground(cornerRadius: cornerRadius))
    }

    // Native placeholder tint is too faint against colored paper.
    func legiblePrompt(_ text: String, visible: Bool, color: Color = Ink.secondary) -> some View {
        overlay(alignment: .leading) {
            if visible {
                Text(text).foregroundStyle(color).lineLimit(1).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
