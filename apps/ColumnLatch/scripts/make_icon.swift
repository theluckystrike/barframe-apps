import AppKit
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.035, green: 0.13, blue: 0.20, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.setFillColor(CGColor(red: 0.08, green: 0.75, blue: 0.68, alpha: 1))
ctx.addPath(CGPath(roundedRect: CGRect(x: 140, y: 150, width: 744, height: 724), cornerWidth: 90, cornerHeight: 90, transform: nil)); ctx.fillPath()
ctx.setFillColor(CGColor(red: 0.05, green: 0.23, blue: 0.28, alpha: 1))
for row in 0..<3 { for col in 0..<3 { ctx.fill(CGRect(x: 210 + col * 210, y: 235 + row * 180, width: 165, height: 130)) } }
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(65); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 490, y: 365)); ctx.addLine(to: CGPoint(x: 600, y: 260)); ctx.addLine(to: CGPoint(x: 830, y: 530)); ctx.strokePath()
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil); CGImageDestinationFinalize(destination)
