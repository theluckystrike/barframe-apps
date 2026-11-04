import AppKit
import CoreGraphics
import Foundation

// HushKey icon: rounded-square, deep navy gradient, a stylized padlock whose
// shackle doubles as a microphone grille arc. Pure Core Graphics, no symbol assets.
let directory = URL(fileURLWithPath: "build/HushKey.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func render(_ size: Int, to name: String) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let boundary = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 180, cornerHeight: 180, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    context.setFillColor(CGColor(red: 0.06, green: 0.10, blue: 0.22, alpha: 1))
    context.addPath(boundary); context.fillPath()
    context.restoreGState()

    context.saveGState(); context.addPath(boundary); context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.16, green: 0.24, blue: 0.46, alpha: 1), CGColor(red: 0.04, green: 0.07, blue: 0.16, alpha: 1)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    context.restoreGState()

    // Shackle (open arc)
    context.setLineCap(.round)
    context.setStrokeColor(CGColor(red: 0.55, green: 0.62, blue: 0.78, alpha: 1))
    context.setLineWidth(56)
    context.addArc(center: CGPoint(x: 512, y: 620), radius: 130, startAngle: 0.0, endAngle: .pi, clockwise: false)
    context.strokePath()

    // Body (rounded rect)
    let body = CGPath(roundedRect: CGRect(x: 332, y: 330, width: 360, height: 300), cornerWidth: 64, cornerHeight: 64, transform: nil)
    context.setFillColor(CGColor(red: 0.93, green: 0.96, blue: 1, alpha: 1))
    context.addPath(body); context.fillPath()

    // Keyhole / mic dot
    context.setFillColor(CGColor(red: 0.10, green: 0.55, blue: 0.35, alpha: 1))
    context.fillEllipse(in: CGRect(x: 482, y: 500, width: 60, height: 60))
    context.setLineCap(.round)
    context.setStrokeColor(CGColor(red: 0.10, green: 0.55, blue: 0.35, alpha: 1))
    context.setLineWidth(26)
    context.move(to: CGPoint(x: 512, y: 480)); context.addLine(to: CGPoint(x: 512, y: 400)); context.strokePath()

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
print("icon ok")
