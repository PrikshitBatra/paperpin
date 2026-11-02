import SwiftUI

private func adaptive(_ light: Int, _ dark: Int) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let code = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(cgColor: PaperArt.color(code))!
    })
}

enum Ink {
    static let text = adaptive(0x2E352D, 0xEFF0E7)
    static let secondary = adaptive(0x586152, 0xC1C8B9)
    static let faint = adaptive(0x696F62, 0xAAB39F)
    static let canvas = adaptive(0xFAFAF6, 0x262923)
    static let sidebar = adaptive(0xEFF0E8, 0x1D211C)
    static let surface = adaptive(0xFFFFFC, 0x30352D)
    static let line = adaptive(0xDADCD2, 0x43493D)
    static let selected = adaptive(0xDCE4D5, 0x354431)
    static let accent = adaptive(0x354D39, 0xC5DAB4)
    static let onAccent = adaptive(0xFFFFF6, 0x23351E)
    static let greenDot = adaptive(0x55774E, 0xA3C391)
    static let warning = adaptive(0x98522C, 0xF0BA8C)
}

extension PaperColor {
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
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold))
            .tracking(1.3).foregroundStyle(Ink.faint)
    }
}

struct ActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).frame(height: 34)
            .foregroundStyle(Ink.onAccent)
            .background(RoundedRectangle(cornerRadius: 8).fill(Ink.accent))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(Rectangle())
    }
}

struct TaskCheck: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false
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
    var body: some View {
        Text("\(count)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
            .foregroundStyle(Ink.secondary).padding(.horizontal, 6).frame(minWidth: 21, minHeight: 17)
            .background(Capsule().fill(Ink.text.opacity(0.065)))
    }
}

func plural(_ count: Int, _ one: String, _ many: String) -> String {
    "\(count) \(count == 1 ? one : many)"
}

extension View {
    // Native placeholder tint is too faint against colored paper.
    func legiblePrompt(_ text: String, visible: Bool, color: Color = Ink.secondary) -> some View {
        overlay(alignment: .leading) {
            if visible {
                Text(text).foregroundStyle(color).lineLimit(1).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
