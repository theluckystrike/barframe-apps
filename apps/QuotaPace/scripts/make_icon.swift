import AppKit
import Foundation
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon surface creation failed") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let shape = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.27)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor(calibratedRed: 0.2, green: 0.18, blue: 0.55, alpha: 1).setFill(); shape.fill()
NSGraphicsContext.restoreGraphicsState()
let gradient = NSGradient(colors: [NSColor(calibratedRed: 94/255, green: 92/255, blue: 230/255, alpha: 1), NSColor(calibratedRed: 43/255, green: 42/255, blue: 158/255, alpha: 1)])!
gradient.draw(in: shape, angle: -60)
// Original open dial, three broad ticks and a rising needle; clear at 32 px.
NSColor.white.setStroke()
let dial = NSBezierPath()
dial.lineWidth = 48
dial.lineCapStyle = .round
dial.appendArc(withCenter: NSPoint(x: 512, y: 480), radius: 246, startAngle: 215, endAngle: -35, clockwise: true)
dial.stroke()
for angle in [150.0, 90.0, 30.0] {
    let radians = angle * .pi / 180
    let tick = NSBezierPath()
    tick.lineWidth = 28; tick.lineCapStyle = .round
    tick.move(to: NSPoint(x: 512 + 180 * cos(radians), y: 480 + 180 * sin(radians)))
    tick.line(to: NSPoint(x: 512 + 210 * cos(radians), y: 480 + 210 * sin(radians)))
    tick.stroke()
}
let needle = NSBezierPath()
needle.move(to: NSPoint(x: 485, y: 453))
needle.line(to: NSPoint(x: 652, y: 627))
needle.line(to: NSPoint(x: 539, y: 507))
needle.close()
NSColor.white.setFill(); needle.fill()
let shaft = NSBezierPath()
shaft.lineWidth = 36; shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 512, y: 480)); shaft.line(to: NSPoint(x: 644, y: 618)); shaft.stroke()
NSBezierPath(ovalIn: NSRect(x: 465, y: 433, width: 94, height: 94)).fill()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
let output = URL(fileURLWithPath: "assets/AppIcon-1024.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: output, options: .atomic)
