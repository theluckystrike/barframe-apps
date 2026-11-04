import AppKit
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 320, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.systemBlue.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 480, height: 320)).fill()
NSColor.systemTeal.setFill(); NSBezierPath(ovalIn: NSRect(x: 65, y: 170, width: 85, height: 85)).fill()
NSColor.white.withAlphaComponent(0.8).setFill()
let path = NSBezierPath(); path.move(to: NSPoint(x: 0, y: 0)); path.line(to: NSPoint(x: 200, y: 230)); path.line(to: NSPoint(x: 320, y: 80)); path.line(to: NSPoint(x: 400, y: 160)); path.line(to: NSPoint(x: 480, y: 0)); path.close(); path.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
