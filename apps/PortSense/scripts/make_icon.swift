import AppKit

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Bitmap allocation failed") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
shadow.shadowBlurRadius = 32
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSColor(calibratedRed: 0, green: 113 / 255, blue: 164 / 255, alpha: 1).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
let gradient = NSGradient(starting: NSColor(calibratedRed: 100 / 255, green: 210 / 255, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0, green: 113 / 255, blue: 164 / 255, alpha: 1))!
gradient.draw(in: tile, angle: -65)
// Original connector artwork: a broad socket, three contacts and an asymmetric cable loop.
// Every shape is drawn here from geometric primitives.
let cable = NSBezierPath()
cable.move(to: NSPoint(x: 512, y: 438))
cable.curve(to: NSPoint(x: 674, y: 245), controlPoint1: NSPoint(x: 512, y: 332), controlPoint2: NSPoint(x: 758, y: 349))
cable.curve(to: NSPoint(x: 318, y: 286), controlPoint1: NSPoint(x: 616, y: 156), controlPoint2: NSPoint(x: 380, y: 197))
cable.lineWidth = 64
cable.lineCapStyle = .round
NSColor.white.setStroke(); cable.stroke()
let shoulder = NSBezierPath(roundedRect: NSRect(x: 412, y: 405, width: 200, height: 110), xRadius: 44, yRadius: 44)
NSColor.white.setFill(); shoulder.fill()
let shell = NSBezierPath(roundedRect: NSRect(x: 283, y: 475, width: 458, height: 272), xRadius: 76, yRadius: 76)
shell.fill()
let socket = NSBezierPath(roundedRect: NSRect(x: 345, y: 588, width: 334, height: 97), xRadius: 42, yRadius: 42)
NSColor(calibratedRed: 0, green: 113 / 255, blue: 164 / 255, alpha: 1).setFill(); socket.fill()
NSColor(calibratedRed: 100 / 255, green: 210 / 255, blue: 1, alpha: 1).setFill()
for x in [403, 487, 571] {
    NSBezierPath(roundedRect: NSRect(x: x, y: 607, width: 50, height: 59), xRadius: 12, yRadius: 12).fill()
}
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
try png.write(to: root.appendingPathComponent("assets/AppIcon-1024.png"), options: .atomic)
print("Generated assets/AppIcon-1024.png")
