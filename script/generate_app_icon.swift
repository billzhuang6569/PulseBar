import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsDir = root.appendingPathComponent("Assets", isDirectory: true)
let iconsetDir = assetsDir.appendingPathComponent("ZhuangStatusBar.iconset", isDirectory: true)
let outputIcon = assetsDir.appendingPathComponent("ZhuangStatusBar.icns")

try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: outputIcon)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(size: Int) -> NSImage {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: side, height: side)
    NSColor.clear.setFill()
    canvas.fill()

    let outer = canvas.insetBy(dx: side * 0.055, dy: side * 0.055)
    let outerPath = roundedRect(outer, radius: side * 0.22)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = side * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
    shadow.set()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.075, alpha: 1),
        NSColor(calibratedRed: 0.035, green: 0.23, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.50, alpha: 1)
    ])?.draw(in: outerPath, angle: -38)
    NSGraphicsContext.restoreGraphicsState()

    let highlightPath = roundedRect(outer.insetBy(dx: side * 0.025, dy: side * 0.025), radius: side * 0.18)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    highlightPath.lineWidth = max(1, side * 0.006)
    highlightPath.stroke()

    let menuRect = NSRect(
        x: outer.minX + side * 0.11,
        y: outer.maxY - side * 0.23,
        width: outer.width - side * 0.22,
        height: side * 0.095
    )
    NSColor.white.withAlphaComponent(0.16).setFill()
    roundedRect(menuRect, radius: side * 0.045).fill()

    for index in 0..<3 {
        let dot = NSRect(
            x: menuRect.minX + side * 0.035 + CGFloat(index) * side * 0.052,
            y: menuRect.midY - side * 0.014,
            width: side * 0.028,
            height: side * 0.028
        )
        NSColor.white.withAlphaComponent(0.70).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    let glyph = "庄"
    let font = NSFont(name: "PingFangSC-Semibold", size: side * 0.43)
        ?? NSFont.systemFont(ofSize: side * 0.43, weight: .semibold)
    let glyphAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let attributedGlyph = NSAttributedString(string: glyph, attributes: glyphAttributes)
    let glyphSize = attributedGlyph.size()
    attributedGlyph.draw(
        at: NSPoint(
            x: outer.midX - glyphSize.width / 2,
            y: outer.midY - glyphSize.height * 0.44
        )
    )

    let lineY = outer.minY + side * 0.21
    let linePath = NSBezierPath()
    linePath.move(to: NSPoint(x: outer.minX + side * 0.17, y: lineY))
    linePath.line(to: NSPoint(x: outer.minX + side * 0.30, y: lineY))
    linePath.line(to: NSPoint(x: outer.minX + side * 0.36, y: lineY + side * 0.052))
    linePath.line(to: NSPoint(x: outer.minX + side * 0.44, y: lineY - side * 0.048))
    linePath.line(to: NSPoint(x: outer.minX + side * 0.52, y: lineY + side * 0.035))
    linePath.line(to: NSPoint(x: outer.maxX - side * 0.17, y: lineY))
    NSColor(calibratedRed: 0.75, green: 1.0, blue: 0.90, alpha: 0.92).setStroke()
    linePath.lineWidth = max(2, side * 0.018)
    linePath.lineCapStyle = .round
    linePath.lineJoinStyle = .round
    linePath.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render PNG"])
    }

    try png.write(to: url)
}

for (filename, size) in sizes {
    try writePNG(drawIcon(size: size), to: iconsetDir.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputIcon.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print(outputIcon.path)
