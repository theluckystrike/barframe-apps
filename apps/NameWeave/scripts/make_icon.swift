import AppKit
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.035, green: 0.14, blue: 0.19, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.setLineCap(.round); ctx.setLineJoin(.round)
// Three woven paths with deliberately separated endpoints.
for (offset, color) in [(CGFloat(0), CGColor(red: 0.24, green: 0.91, blue: 0.73, alpha: 1)), (CGFloat(155), CGColor(red: 0.39, green: 0.68, blue: 1, alpha: 1)), (CGFloat(310), CGColor(red: 0.95, green: 0.82, blue: 0.43, alpha: 1))] {
    ctx.setStrokeColor(color); ctx.setLineWidth(70)
    ctx.move(to: CGPoint(x: 235, y: 330 + offset)); ctx.addLine(to: CGPoint(x: 415, y: 330 + offset)); ctx.addCurve(to: CGPoint(x: 630, y: 670 - offset), control1: CGPoint(x: 485, y: 330 + offset), control2: CGPoint(x: 525, y: 670 - offset)); ctx.addLine(to: CGPoint(x: 785, y: 670 - offset)); ctx.strokePath()
    ctx.setFillColor(color); ctx.fillEllipse(in: CGRect(x: 175, y: 285 + offset, width: 90, height: 90))
}
let image = ctx.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
