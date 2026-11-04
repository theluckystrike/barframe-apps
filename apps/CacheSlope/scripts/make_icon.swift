import AppKit
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
c.setFillColor(CGColor(red: 0.035, green: 0.11, blue: 0.15, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: size, height: size))
c.setFillColor(CGColor(red: 0.10, green: 0.35, blue: 0.40, alpha: 1)); c.addPath(CGPath(roundedRect: CGRect(x: 160, y: 230, width: 704, height: 540), cornerWidth: 70, cornerHeight: 70, transform: nil)); c.fillPath()
c.setFillColor(CGColor(red: 0.2, green: 0.78, blue: 0.70, alpha: 1)); c.addPath(CGPath(roundedRect: CGRect(x: 160, y: 690, width: 300, height: 140), cornerWidth: 45, cornerHeight: 45, transform: nil)); c.fillPath()
for (x,h) in [(280,180),(450,300),(620,420)] { c.setFillColor(CGColor(red: 0.45, green: 0.94, blue: 0.81, alpha: 1)); c.addPath(CGPath(roundedRect: CGRect(x: x, y: 310, width: 110, height: h), cornerWidth: 24, cornerHeight: 24, transform: nil)); c.fillPath() }
let out = URL(fileURLWithPath: CommandLine.arguments[1]); let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, c.makeImage()!, nil); precondition(CGImageDestinationFinalize(dest))
