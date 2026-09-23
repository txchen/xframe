import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/check-app-icon.swift /absolute/path/to/XFrame.app\n", stderr)
    exit(2)
}

let appPath = CommandLine.arguments[1]
let icnsPath = appPath + "/Contents/Resources/AppIcon.icns"

func greenPixels(_ image: NSImage) -> Int {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
    NSGraphicsContext.restoreGraphicsState()
    var count = 0
    for y in 0..<64 {
        for x in 0..<64 {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.greenComponent > 0.35 && color.greenComponent > color.redComponent * 1.3 &&
                color.greenComponent > color.blueComponent * 1.3 { count += 1 }
        }
    }
    return count
}

let fileIcon = NSImage(contentsOfFile: icnsPath)!
let workspaceIcon = NSWorkspace.shared.icon(forFile: appPath)
let sourceGreenPixels = greenPixels(fileIcon)
let appGreenPixels = greenPixels(workspaceIcon)
print("icns green pixels: \(sourceGreenPixels)")
print("app green pixels: \(appGreenPixels)")
guard sourceGreenPixels > 100, appGreenPixels > 100 else { exit(1) }
