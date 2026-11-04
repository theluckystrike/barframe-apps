import AppKit
import CoreGraphics
import Foundation

// Draw a night sky: deep indigo gradient, crescent moon, three stars.
let directory = URL(fileURLWithPath: "build/Starglass.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func render(_ size: Int, to name: String) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let boundary = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 180, cornerHeight: 180, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    context.setFillColor(CGColor(red: 0.03, green: 0.04, blue: 0.12, alpha: 1))
    context.addPath(boundary); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(boundary); context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.10, green: 0.12, blue: 0.30, alpha: 1), CGColor(red: 0.02, green: 0.03, blue: 0.09, alpha: 1)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    // Stars
    context.setFillColor(CGColor(red: 1, green: 1, blue: 0.95, alpha: 1))
    for (x, y, r) in [(280.0, 760.0, 14.0), (700.0, 820.0, 11.0), (420.0, 620.0, 9.0), (760.0, 560.0, 12.0)] {
        context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }
    // Crescent moon: full pale disc minus offset sky-coloured disc
    context.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.86, alpha: 1))
    context.fillEllipse(in: CGRect(x: 320, y: 300, width: 380, height: 380))
    context.setFillColor(CGColor(red: 0.03, green: 0.04, blue: 0.10, alpha: 1))
    context.fillEllipse(in: CGRect(x: 430, y: 360, width: 340, height: 340))
    context.restoreGState()
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
