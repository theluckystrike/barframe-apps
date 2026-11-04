import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let c = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
c.setFillColor(CGColor(red: 0.055, green: 0.16, blue: 0.20, alpha: 1)); c.fill(CGRect(x: 0,y: 0,width: 1024,height: 1024))
c.setFillColor(CGColor(red: 0.16, green: 0.77, blue: 0.65, alpha: 1)); c.addPath(CGPath(roundedRect: CGRect(x: 220,y: 165,width: 585,height: 695),cornerWidth: 85,cornerHeight: 85,transform: nil)); c.fillPath()
c.setFillColor(CGColor(red: 0.90,green: 0.98,blue: 0.95,alpha: 1)); c.addPath(CGPath(roundedRect: CGRect(x: 165,y: 210,width: 585,height: 650),cornerWidth: 70,cornerHeight: 70,transform: nil)); c.fillPath()
c.setStrokeColor(CGColor(red: 0.06,green: 0.32,blue: 0.34,alpha: 1)); c.setLineWidth(34); c.setLineCap(.round); c.setLineJoin(.round)
for y in [360.0, 520.0, 680.0] { c.move(to: CGPoint(x: 250,y: y)); c.addLine(to: CGPoint(x: 285,y: y-35)); c.addLine(to: CGPoint(x: 340,y: y+35)); c.strokePath(); c.move(to: CGPoint(x: 415,y: y)); c.addLine(to: CGPoint(x: 640,y: y)); c.strokePath() }
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest,c.makeImage()!,nil); CGImageDestinationFinalize(dest)
