import AppKit
import CoreGraphics
import Foundation

// Draw original converging paths and a check. Use no symbol assets.
let directory = URL(fileURLWithPath: "build/ArmReady.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func render(_ size: Int, to name: String) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let boundary = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 180, cornerHeight: 180, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    context.setFillColor(CGColor(red: 0.05, green: 0.2, blue: 0.2, alpha: 1))
    context.addPath(boundary); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(boundary); context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.05, green: 0.4, blue: 0.38, alpha: 1), CGColor(red: 0.02, green: 0.12, blue: 0.14, alpha: 1)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    context.restoreGState()
    context.setLineCap(.round); context.setLineJoin(.round)
    context.setStrokeColor(CGColor(red: 0.24, green: 0.76, blue: 0.7, alpha: 1)); context.setLineWidth(38)
    for y: CGFloat in [340, 684] {
        context.move(to: CGPoint(x: 254, y: y)); context.addLine(to: CGPoint(x: 380, y: y)); context.addLine(to: CGPoint(x: 504, y: 512)); context.strokePath()
    }
    context.setStrokeColor(CGColor(red: 0.91, green: 1, blue: 0.98, alpha: 1)); context.setLineWidth(62)
    context.move(to: CGPoint(x: 480, y: 505)); context.addLine(to: CGPoint(x: 579, y: 404)); context.addLine(to: CGPoint(x: 768, y: 632)); context.strokePath()
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
