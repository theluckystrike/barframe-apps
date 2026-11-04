import AppKit
import CoreGraphics
import Foundation
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let variants = [(16, "icon_16x16.png"), (32, "icon_16x16@2x.png"), (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"), (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"), (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"), (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")]
for (size, name) in variants {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let unit = CGFloat(size) / 1024
    context.scaleBy(x: unit, y: unit)
    context.setFillColor(CGColor(red: 0.04, green: 0.11, blue: 0.18, alpha: 1))
    context.addPath(CGPath(roundedRect: CGRect(x: 30, y: 30, width: 964, height: 964), cornerWidth: 205, cornerHeight: 205, transform: nil)); context.fillPath()
    context.setStrokeColor(CGColor(red: 0.14, green: 0.83, blue: 0.92, alpha: 1)); context.setLineWidth(60); context.setLineCap(.round); context.setLineJoin(.round)
    context.move(to: CGPoint(x: 170, y: 480)); context.addLine(to: CGPoint(x: 305, y: 480))
    context.addLine(to: CGPoint(x: 395, y: 690)); context.addLine(to: CGPoint(x: 535, y: 310)); context.addLine(to: CGPoint(x: 640, y: 480)); context.addLine(to: CGPoint(x: 785, y: 480)); context.strokePath()
    context.setFillColor(CGColor(red: 1, green: 0.65, blue: 0.18, alpha: 1)); context.fillEllipse(in: CGRect(x: 690, y: 680, width: 150, height: 150))
    let representation = NSBitmapImageRep(cgImage: context.makeImage()!)
    try representation.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
}
