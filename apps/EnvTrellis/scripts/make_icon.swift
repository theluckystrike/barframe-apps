import AppKit
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments[1]
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let bounds = CGRect(x: 0, y: 0, width: size, height: size)
context.addPath(CGPath(roundedRect: bounds.insetBy(dx: 16, dy: 16), cornerWidth: 210, cornerHeight: 210, transform: nil))
context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.07, green: 0.36, blue: 0.25, alpha: 1), CGColor(red: 0.04, green: 0.13, blue: 0.18, alpha: 1)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: .zero, options: [])
context.setStrokeColor(CGColor(red: 0.36, green: 0.77, blue: 0.55, alpha: 0.3))
context.setLineWidth(14)
for x in [270, 510, 750] { context.move(to: CGPoint(x: x, y: 200)); context.addLine(to: CGPoint(x: x, y: 800)); context.strokePath() }
for y in [300, 500, 700] { context.move(to: CGPoint(x: 190, y: y)); context.addLine(to: CGPoint(x: 825, y: y)); context.strokePath() }
context.setStrokeColor(CGColor(red: 0.87, green: 1, blue: 0.88, alpha: 1)); context.setLineWidth(30); context.setLineCap(.round)
context.move(to: CGPoint(x: 380, y: 230)); context.addCurve(to: CGPoint(x: 655, y: 775), control1: CGPoint(x: 410, y: 520), control2: CGPoint(x: 605, y: 630)); context.strokePath()
func leaf(_ x: CGFloat, _ y: CGFloat, left: Bool) {
    let path = CGMutablePath(); let direction: CGFloat = left ? -1 : 1
    path.move(to: CGPoint(x: x, y: y))
    path.addCurve(to: CGPoint(x: x + direction * 220, y: y + 120), control1: CGPoint(x: x + direction * 140, y: y - 25), control2: CGPoint(x: x + direction * 235, y: y + 30))
    path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x + direction * 60, y: y + 160), control2: CGPoint(x: x + direction * 15, y: y + 95))
    context.addPath(path); context.setFillColor(CGColor(red: left ? 0.47 : 0.7, green: 0.94, blue: 0.64, alpha: 1)); context.fillPath()
}
leaf(410, 360, left: true); leaf(475, 480, left: false); leaf(585, 635, left: true)
context.setStrokeColor(CGColor(red: 0.93, green: 1, blue: 0.94, alpha: 1)); context.setLineWidth(33)
context.move(to: CGPoint(x: 630, y: 275)); context.addLine(to: CGPoint(x: 685, y: 225)); context.addLine(to: CGPoint(x: 805, y: 365)); context.strokePath()
let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))
