import AppKit
import MetalKit

@MainActor
enum TestPattern {
    static let width = 1920
    static let height = 1080

    static func makeTexture(device: any MTLDevice) throws -> any MTLTexture {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RenderError.unavailable("Unable to allocate the test pattern.") }

        // Generate once on the CPU. Resizing only changes GPU presentation.
        context.setFillColor(CGColor(red: 0.035, green: 0.055, blue: 0.085, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(gray: 0.24, alpha: 1))
        context.setLineWidth(1)
        for x in stride(from: 0, through: width, by: 120) {
            context.move(to: CGPoint(x: CGFloat(x) + 0.5, y: 0))
            context.addLine(to: CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(height)))
        }
        for y in stride(from: 0, through: height, by: 120) {
            context.move(to: CGPoint(x: 0, y: CGFloat(y) + 0.5))
            context.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(y) + 0.5))
        }
        context.strokePath()

        context.setStrokeColor(CGColor(red: 0.2, green: 0.85, blue: 0.7, alpha: 1))
        context.setLineWidth(5)
        for diameter in [480, 600] {
            context.strokeEllipse(in: CGRect(x: (width - diameter) / 2, y: (height - diameter) / 2, width: diameter, height: diameter))
        }
        let colors: [NSColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue]
        for (index, color) in colors.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 540 + index * 120, y: 160, width: 120, height: 64))
        }

        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(4)
        context.stroke(CGRect(x: 2, y: 2, width: width - 4, height: height - 4))
        for x in [12, width - 60] {
            for y in [12, height - 60] {
                context.setFillColor(CGColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 48, height: 48))
            }
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        func label(_ text: String, y: CGFloat, size: CGFloat, color: NSColor = .white) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
                .foregroundColor: color
            ]
            let string = text as NSString
            let dimensions = string.size(withAttributes: attributes)
            string.draw(at: CGPoint(x: (CGFloat(width) - dimensions.width) / 2, y: y), withAttributes: attributes)
        }
        label("XFRAME", y: 550, size: 56)
        label("1920 × 1080  /  16:9", y: 495, size: 26)
        label("STATIC TEST PATTERN", y: 930, size: 30)
        label("TOP", y: 1020, size: 20)
        label("ASPECT FIT  •  120 PX GRID  •  ALL FOUR CORNERS VISIBLE", y: 80, size: 22)
        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage() else {
            throw RenderError.unavailable("Unable to create the test pattern image.")
        }
        return try MTKTextureLoader(device: device).newTexture(cgImage: image, options: [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ])
    }
}
