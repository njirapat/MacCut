// Render the app icon into an .iconset folder: metal-bladed scissors with orange handles
// on a blue rounded square, in the style of Apple's object icons.
// The scissors are drawn from basic shapes, not from SF Symbols (Apple does not allow SF Symbols in app icons).
// Usage: swift make-icon.swift <output.iconset>

import AppKit

let output = CommandLine.arguments[1]
let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func bitmap(_ pixels: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

/// Scissors in the 1024-point canvas: blades pointing up-right, handles down-left.
func scissors() -> (blades: NSBezierPath, handles: NSBezierPath, holes: NSBezierPath) {
    let blades = NSBezierPath(), handles = NSBezierPath()
    let holes = NSBezierPath(ovalIn: NSRect(x: -15, y: -15, width: 30, height: 30))   // pivot screw
    for side: CGFloat in [-1, 1] {
        // Blade: wide at the pivot, tapering to a rounded point; each tilts 13 degrees from vertical.
        let blade = NSBezierPath()
        blade.move(to: NSPoint(x: -34, y: -20))
        blade.line(to: NSPoint(x: 34, y: -20))
        blade.curve(to: NSPoint(x: 6, y: 380), controlPoint1: NSPoint(x: 40, y: 160), controlPoint2: NSPoint(x: 22, y: 300))
        blade.curve(to: NSPoint(x: -6, y: 380), controlPoint1: NSPoint(x: 2, y: 392), controlPoint2: NSPoint(x: -2, y: 392))
        blade.curve(to: NSPoint(x: -34, y: -20), controlPoint1: NSPoint(x: -22, y: 300), controlPoint2: NSPoint(x: -40, y: 160))
        blade.close()
        var tilt = AffineTransform()
        tilt.rotate(byDegrees: side * 13)
        blade.transform(using: tilt)
        blades.append(blade)

        // Handle: an arm from the pivot to a finger ring; each tilts 24 degrees from straight down.
        let center = NSPoint(x: 0, y: -250)
        let arm = NSBezierPath(roundedRect: NSRect(x: -26, y: -190, width: 52, height: 200), xRadius: 26, yRadius: 26)
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 100, y: center.y - 100, width: 200, height: 200))
        let hole = NSBezierPath(ovalIn: NSRect(x: center.x - 58, y: center.y - 58, width: 116, height: 116))
        var spread = AffineTransform()
        spread.rotate(byDegrees: -side * 24)
        for part in [arm, ring, hole] { part.transform(using: spread) }
        handles.append(arm)
        handles.append(ring)
        holes.append(hole)
    }
    var place = AffineTransform()
    place.translate(x: 512, y: 512)
    place.rotate(byDegrees: -45)
    place.translate(x: 0, y: 30)   // shift along the axis so blades and handles are centered
    for path in [blades, handles, holes] { path.transform(using: place) }
    return (blades, handles, holes)
}

/// Full-size 1024px master; smaller sizes are scaled down from it.
func renderMaster() -> NSBitmapImageRep {
    let rep = bitmap(1024)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context

    // Background: blue rounded square (macOS icon grid, 824 of 1024 points) with light from the top.
    let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
    NSGradient(starting: rgb(88, 170, 255), ending: rgb(48, 84, 220))!.draw(in: squircle, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(starting: rgb(255, 255, 255, 0.25), ending: rgb(255, 255, 255, 0))!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Scissors on their own layer: orange handles, brushed-metal blades with a top highlight, holes punched out.
    let parts = scissors()
    let layer = bitmap(1024)
    NSGraphicsContext.saveGraphicsState()
    let layerContext = NSGraphicsContext(bitmapImageRep: layer)!
    NSGraphicsContext.current = layerContext
    NSGradient(starting: rgb(255, 170, 70), ending: rgb(240, 110, 20))!.draw(in: parts.handles, angle: -90)
    NSGradient(colors: [rgb(250, 251, 253), rgb(196, 202, 212), rgb(236, 239, 244), rgb(160, 168, 180)],
               atLocations: [0, 0.45, 0.6, 1], colorSpace: .sRGB)!.draw(in: parts.blades, angle: 0)
    rgb(90, 98, 112, 0.5).setStroke()
    parts.blades.lineWidth = 3
    parts.blades.stroke()
    NSGraphicsContext.saveGraphicsState()
    parts.blades.addClip()
    NSGradient(starting: rgb(255, 255, 255, 0.45), ending: rgb(255, 255, 255, 0))!
        .draw(in: NSRect(x: 0, y: 560, width: 1024, height: 464), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    layerContext.compositingOperation = .clear
    parts.holes.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Composite the scissors with a soft drop shadow.
    NSGraphicsContext.current = context
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -22)
    shadow.shadowColor = NSColor(white: 0, alpha: 0.4)
    shadow.set()
    layer.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), from: .zero,
               operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func scaled(_ master: NSBitmapImageRep, to pixels: Int) -> Data {
    let rep = bitmap(pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero,
                operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let master = renderMaster()
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for (name, pixels) in sizes {
    try scaled(master, to: pixels).write(to: URL(fileURLWithPath: "\(output)/icon_\(name).png"))
}
