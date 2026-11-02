import AppKit

enum PaperArt {
    static func color(_ hex: Int) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    // All drawing coordinates run down from the top of a 100-point square.
    static func icon(_ ctx: CGContext, size: CGFloat) {
        ctx.saveGState()
        ctx.scaleBy(x: size / 100, y: size / 100)
        let tile = CGPath(roundedRect: CGRect(x: 5, y: 5, width: 90, height: 90),
                          cornerWidth: 21, cornerHeight: 21, transform: nil)
        ctx.addPath(tile)
        ctx.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: [color(0x526A48), color(0x293B2D)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 4, y: 2), end: CGPoint(x: 95, y: 98), options: [])
        ctx.saveGState()
        ctx.translateBy(x: 45, y: 51)
        ctx.rotate(by: -0.16)
        ctx.setFillColor(color(0xC6AD67))
        ctx.addPath(CGPath(roundedRect: CGRect(x: -24, y: -23, width: 48, height: 52),
                           cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.translateBy(x: 53, y: 48)
        ctx.rotate(by: 0.065)
        ctx.move(to: CGPoint(x: -24, y: -24))
        ctx.addQuadCurve(to: CGPoint(x: -20, y: -28), control: CGPoint(x: -24, y: -28))
        ctx.addLine(to: CGPoint(x: 20, y: -28))
        ctx.addQuadCurve(to: CGPoint(x: 24, y: -24), control: CGPoint(x: 24, y: -28))
        ctx.addLine(to: CGPoint(x: 24, y: 13))
        ctx.addLine(to: CGPoint(x: 10, y: 27))
        ctx.addLine(to: CGPoint(x: -20, y: 27))
        ctx.addQuadCurve(to: CGPoint(x: -24, y: 23), control: CGPoint(x: -24, y: 27))
        ctx.closePath()
        ctx.setFillColor(color(0xF9E7A0))
        ctx.fillPath()
        ctx.move(to: CGPoint(x: 10, y: 27))
        ctx.addLine(to: CGPoint(x: 10, y: 16))
        ctx.addQuadCurve(to: CGPoint(x: 13, y: 13), control: CGPoint(x: 10, y: 13))
        ctx.addLine(to: CGPoint(x: 24, y: 13))
        ctx.closePath()
        ctx.setFillColor(color(0xD3AD53))
        ctx.fillPath()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(4.8)
        ctx.setStrokeColor(color(0x394936))
        ctx.move(to: CGPoint(x: -12, y: -2))
        ctx.addLine(to: CGPoint(x: -5.5, y: 4.5))
        ctx.addLine(to: CGPoint(x: 8, y: -10))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static let mark = NSImage(size: NSSize(width: 40, height: 40), flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        icon(ctx, size: 40)
        return true
    }

    static let menuMark: NSImage = {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.setLineWidth(1.45)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            c.setStrokeColor(NSColor.black.cgColor)
            c.move(to: CGPoint(x: 2.2, y: 4.8))
            c.addLine(to: CGPoint(x: 2.2, y: 13.6))
            c.addQuadCurve(to: CGPoint(x: 4.5, y: 16), control: CGPoint(x: 2.2, y: 16))
            c.addLine(to: CGPoint(x: 11.4, y: 16))
            c.strokePath()
            c.move(to: CGPoint(x: 5.2, y: 12))
            c.addLine(to: CGPoint(x: 5.2, y: 3.4))
            c.addQuadCurve(to: CGPoint(x: 6.8, y: 1.8), control: CGPoint(x: 5.2, y: 1.8))
            c.addLine(to: CGPoint(x: 15.6, y: 1.8))
            c.addQuadCurve(to: CGPoint(x: 17.2, y: 3.4), control: CGPoint(x: 17.2, y: 1.8))
            c.addLine(to: CGPoint(x: 17.2, y: 9.7))
            c.addLine(to: CGPoint(x: 13.2, y: 13.7))
            c.addLine(to: CGPoint(x: 6.8, y: 13.7))
            c.addQuadCurve(to: CGPoint(x: 5.2, y: 12), control: CGPoint(x: 5.2, y: 13.7))
            c.closePath()
            c.strokePath()
            c.move(to: CGPoint(x: 8.2, y: 7.4))
            c.addLine(to: CGPoint(x: 10, y: 9.1))
            c.addLine(to: CGPoint(x: 13.6, y: 5.5))
            c.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Paperpin"
        return image
    }()
}
