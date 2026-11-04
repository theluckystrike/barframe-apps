import AppKit
import ImageIO
import UniformTypeIdentifiers
let size=1024
let c=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
c.setFillColor(CGColor(red:0.035,green:0.10,blue:0.15,alpha:1)); c.fill(CGRect(x:0,y:0,width:size,height:size))
c.setFillColor(CGColor(red:0.08,green:0.29,blue:0.34,alpha:1)); c.addPath(CGPath(roundedRect:CGRect(x:90,y:90,width:844,height:844),cornerWidth:180,cornerHeight:180,transform:nil)); c.fillPath()
c.setStrokeColor(CGColor(red:0.3,green:0.92,blue:0.78,alpha:1)); c.setLineWidth(66); c.setLineCap(.round); c.setLineJoin(.round)
c.move(to:CGPoint(x:240,y:480)); c.addLine(to:CGPoint(x:430,y:300)); c.addLine(to:CGPoint(x:770,y:700)); c.strokePath()
c.setStrokeColor(CGColor(red:0.94,green:0.7,blue:0.3,alpha:1)); c.setLineWidth(26)
c.move(to:CGPoint(x:230,y:220)); c.addLine(to:CGPoint(x:790,y:220)); c.strokePath()
let image=c.makeImage()!
let output=URL(fileURLWithPath:CommandLine.arguments[1])
let dest=CGImageDestinationCreateWithURL(output as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,image,nil); if !CGImageDestinationFinalize(dest) { exit(1) }
