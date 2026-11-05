import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.025, green: 0.17, blue: 0.15, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let background = CGPath(roundedRect: CGRect(x: 42, y: 42, width: 940, height: 940), cornerWidth: 205, cornerHeight: 205, transform: nil)
context.addPath(background); context.setFillColor(CGColor(red: 0.07, green: 0.31, blue: 0.26, alpha: 1)); context.fillPath()
context.setStrokeColor(CGColor(red: 0.64, green: 0.98, blue: 0.81, alpha: 1)); context.setLineWidth(64); context.setLineCap(.round)
for rect in [CGRect(x: 205, y: 350, width: 355, height: 225), CGRect(x: 470, y: 350, width: 355, height: 225)] {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 112, cornerHeight: 112, transform: nil)); context.strokePath()
}
context.setLineWidth(27); context.move(to: CGPoint(x: 514, y: 590)); context.addLine(to: CGPoint(x: 514, y: 760)); context.strokePath()
context.setFillColor(CGColor(red: 0.56, green: 0.87, blue: 0.39, alpha: 1))
let leaf = CGMutablePath(); leaf.move(to: CGPoint(x: 514, y: 695)); leaf.addCurve(to: CGPoint(x: 690, y: 816), control1: CGPoint(x: 512, y: 792), control2: CGPoint(x: 590, y: 830)); leaf.addCurve(to: CGPoint(x: 514, y: 695), control1: CGPoint(x: 690, y: 733), control2: CGPoint(x: 610, y: 667)); context.addPath(leaf); context.fillPath()
let image = context.makeImage()!
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) { exit(1) }
