import AppKit
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.035, green: 0.095, blue: 0.14, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
func key(_ rect: CGRect, _ color: CGColor) {
    context.setFillColor(color); context.addPath(CGPath(roundedRect: rect, cornerWidth: 58, cornerHeight: 58, transform: nil)); context.fillPath()
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18)); context.setLineWidth(8)
    context.addPath(CGPath(roundedRect: rect.insetBy(dx: 5, dy: 5), cornerWidth: 54, cornerHeight: 54, transform: nil)); context.strokePath()
}
key(CGRect(x: 140, y: 320, width: 460, height: 420), CGColor(red: 0.10, green: 0.72, blue: 0.67, alpha: 1))
key(CGRect(x: 425, y: 175, width: 460, height: 420), CGColor(red: 0.20, green: 0.40, blue: 0.66, alpha: 1))
// Custom crossing key tracks and a shared focus dot.
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.setLineWidth(24); context.setLineCap(.round)
context.move(to: CGPoint(x: 255, y: 575)); context.addLine(to: CGPoint(x: 730, y: 340)); context.strokePath()
context.move(to: CGPoint(x: 280, y: 375)); context.addLine(to: CGPoint(x: 720, y: 570)); context.strokePath()
context.setFillColor(CGColor(red: 1, green: 0.78, blue: 0.24, alpha: 1)); context.fillEllipse(in: CGRect(x: 445, y: 425, width: 114, height: 114))
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
