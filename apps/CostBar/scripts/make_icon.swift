import AppKit
import Foundation

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 38
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.09, alpha: 1).setFill()
tile.fill()
NSShadow().set()
let gradient = NSGradient(colors: [NSColor(calibratedRed: 1, green: 159.0 / 255, blue: 10.0 / 255, alpha: 1), NSColor(calibratedRed: 201.0 / 255, green: 52.0 / 255, blue: 0, alpha: 1)])!
gradient.draw(in: tile, angle: -70)
// Original three-column cost chart, drawn from our own geometry.
NSColor.white.setFill()
for (x, height) in [(CGFloat(268), CGFloat(180)), (CGFloat(442), CGFloat(300)), (CGFloat(616), CGFloat(430))] {
    NSBezierPath(roundedRect: NSRect(x: x, y: 290, width: 140, height: height), xRadius: 26, yRadius: 26).fill()
}
let baseline = NSBezierPath(roundedRect: NSRect(x: 242, y: 228, width: 540, height: 30), xRadius: 15, yRadius: 15)
baseline.fill()
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: "assets/AppIcon-1024.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
print("Generated \(output.path), 1024 × 1024")
