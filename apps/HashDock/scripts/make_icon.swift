import AppKit
import ImageIO
import UniformTypeIdentifiers
let size=1024
let c=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
c.setFillColor(CGColor(red:0.03,green:0.12,blue:0.17,alpha:1)); c.fill(CGRect(x:0,y:0,width:size,height:size))
c.setStrokeColor(CGColor(red:0.2,green:0.87,blue:0.74,alpha:1)); c.setLineWidth(42); c.setLineCap(.round)
for y in [270,510,750] { c.stroke(CGRect(x:190,y:y-60,width:640,height:130)); c.move(to:CGPoint(x:250,y:y)); c.addLine(to:CGPoint(x:440,y:y)); c.strokePath() }
c.setStrokeColor(CGColor(gray:1,alpha:1)); c.setLineWidth(30)
for y in [270,510,750] { c.move(to:CGPoint(x:620,y:y)); c.addLine(to:CGPoint(x:662,y:y-28)); c.addLine(to:CGPoint(x:742,y:y+44)); c.strokePath() }
let out=URL(fileURLWithPath:CommandLine.arguments[1]);let dest=CGImageDestinationCreateWithURL(out as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,c.makeImage()!,nil); CGImageDestinationFinalize(dest)
