import AppKit
import CoreGraphics
import Foundation

// Draw an original pulse/chart mark: rising bars and a heartbeat line. No symbol assets.
let directory = URL(fileURLWithPath: "build/RevPulse.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func render(_ size: Int, to name: String) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let boundary = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 180, cornerHeight: 180, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    context.setFillColor(CGColor(red: 0.09, green: 0.10, blue: 0.22, alpha: 1))
    context.addPath(boundary); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(boundary); context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.16, green: 0.20, blue: 0.42, alpha: 1), CGColor(red: 0.05, green: 0.06, blue: 0.16, alpha: 1)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    context.restoreGState()

    // Rising bars (revenue days).
    let bars: [(x: CGFloat, h: CGFloat)] = [(280, 150), (400, 230), (520, 310), (640, 400)]
    for bar in bars {
        let rect = CGRect(x: bar.x, y: 260, width: 70, height: bar.h)
        let path = CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)
        context.setFillColor(CGColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 0.85))
        context.addPath(path); context.fillPath()
    }
    // Pulse line over the bars.
    context.setLineCap(.round); context.setLineJoin(.round)
    context.setStrokeColor(CGColor(red: 0.45, green: 0.95, blue: 0.75, alpha: 1)); context.setLineWidth(52)
    context.move(to: CGPoint(x: 250, y: 560))
    context.addLine(to: CGPoint(x: 370, y: 560))
    context.addLine(to: CGPoint(x: 450, y: 440))
    context.addLine(to: CGPoint(x: 540, y: 680))
    context.addLine(to: CGPoint(x: 630, y: 480))
    context.addLine(to: CGPoint(x: 700, y: 560))
    context.addLine(to: CGPoint(x: 780, y: 560))
    context.strokePath()
    let image = context.makeImage()!
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try png.write(to: directory.appendingPathComponent(name))
}
for size in [16, 32, 128, 256, 512] {
    try render(size, to: "icon_\(size)x\(size).png")
    try render(size * 2, to: "icon_\(size)x\(size)@2x.png")
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", directory.path, "-o", "Resources/AppIcon.icns"]
try task.run(); task.waitUntilExit()
if task.terminationStatus != 0 { exit(task.terminationStatus) }
