import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
enum MakeIcon {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.translateBy(x: 0, y: CGFloat(pixels))
                ctx.scaleBy(x: 1, y: -1)
                PaperArt.icon(ctx, size: CGFloat(pixels))
                let suffix = scale == 2 ? "@2x" : ""
                let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                let image = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(image, ctx.makeImage()!, nil)
                precondition(CGImageDestinationFinalize(image))
            }
        }
    }
}
