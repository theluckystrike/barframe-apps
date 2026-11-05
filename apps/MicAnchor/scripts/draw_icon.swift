import AppKit
import CoreGraphics

// Original shield and three microphone level bars drawn from geometric paths.
// No system-provided glyph, font character, or external asset is used.
let output = CommandLine.arguments[1]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = graphics
let context = graphics.cgContext
context.setFillColor(CGColor(red: 0.025, green: 0.095, blue: 0.11, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
let background = CGPath(roundedRect: CGRect(x: 40, y: 40, width: 944, height: 944), cornerWidth: 200, cornerHeight: 200, transform: nil)
context.addPath(background); context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    CGColor(red: 0.025, green: 0.25, blue: 0.28, alpha: 1),
    CGColor(red: 0.06, green: 0.48, blue: 0.47, alpha: 1)
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 50, y: 950), end: CGPoint(x: 980, y: 40), options: [])
let shield = CGMutablePath()
shield.move(to: CGPoint(x: 275, y: 676))
shield.addCurve(to: CGPoint(x: 512, y: 810), control1: CGPoint(x: 320, y: 770), control2: CGPoint(x: 414, y: 810))
shield.addCurve(to: CGPoint(x: 768, y: 555), control1: CGPoint(x: 667, y: 810), control2: CGPoint(x: 768, y: 717))
shield.addCurve(to: CGPoint(x: 512, y: 228), control1: CGPoint(x: 785, y: 403), control2: CGPoint(x: 657, y: 290))
shield.addCurve(to: CGPoint(x: 245, y: 470), control1: CGPoint(x: 361, y: 285), control2: CGPoint(x: 248, y: 375))
context.setStrokeColor(CGColor(red: 0.56, green: 0.93, blue: 0.83, alpha: 1))
context.setLineWidth(46); context.setLineCap(.round); context.setLineJoin(.round)
context.addPath(shield); context.strokePath()
context.setFillColor(CGColor(red: 0.93, green: 1, blue: 0.98, alpha: 1))
for bar in [CGRect(x: 390, y: 448, width: 50, height: 150), CGRect(x: 487, y: 384, width: 50, height: 278), CGRect(x: 584, y: 424, width: 50, height: 198)] {
    context.addPath(CGPath(roundedRect: bar, cornerWidth: 25, cornerHeight: 25, transform: nil)); context.fillPath()
}
context.fillEllipse(in: CGRect(x: 214, y: 438, width: 64, height: 64))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
