import AppKit
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.035, green: 0.23, blue: 0.26, alpha: 1))
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerWidth: 208, cornerHeight: 208, transform: nil)); ctx.fillPath()
// A rising pier of three rounded steps with a warm waypoint.
for (x,y,w,h) in [(190.0,220.0,185.0,210.0),(420.0,220.0,185.0,370.0),(650.0,220.0,185.0,530.0)] {
    ctx.setFillColor(CGColor(red: 0.65, green: 0.93, blue: 0.86, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: 40, cornerHeight: 40, transform: nil)); ctx.fillPath()
}
ctx.setFillColor(CGColor(red: 1, green: 0.73, blue: 0.29, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 680, y: 792, width: 124, height: 124))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("Created StepQuay icon")
