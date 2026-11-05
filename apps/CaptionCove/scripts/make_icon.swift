import AppKit
import ImageIO
import UniformTypeIdentifiers
let size=1024
let space=CGColorSpaceCreateDeviceRGB()
let context=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat)->CGColor { CGColor(red:r,green:g,blue:b,alpha:1) }
context.setFillColor(color(0.025,0.12,0.16)); context.fill(CGRect(x:0,y:0,width:size,height:size))
let gradient=CGGradient(colorsSpace:space,colors:[color(0.04,0.48,0.51),color(0.02,0.16,0.26)] as CFArray,locations:[0,1])!
context.drawLinearGradient(gradient,start:CGPoint(x:180,y:1024),end:CGPoint(x:850,y:0),options:[])
// A pair of original cue cards joined by a delivery check. No symbol font assets.
context.setFillColor(color(0.40,0.85,0.78))
context.addPath(CGPath(roundedRect:CGRect(x:145,y:375,width:580,height:405),cornerWidth:62,cornerHeight:62,transform:nil)); context.fillPath()
context.setFillColor(color(0.93,0.99,0.98))
context.addPath(CGPath(roundedRect:CGRect(x:265,y:225,width:605,height:415),cornerWidth:62,cornerHeight:62,transform:nil)); context.fillPath()
context.setFillColor(color(0.04,0.35,0.40))
for (x,y,w) in [(330.0,530.0,175.0),(545.0,530.0,250.0),(330.0,445.0,275.0),(650.0,445.0,145.0)] {
context.addPath(CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:32),cornerWidth:16,cornerHeight:16,transform:nil)); context.fillPath()
}
context.setStrokeColor(color(0.04,0.48,0.44)); context.setLineWidth(38); context.setLineCap(.round); context.setLineJoin(.round)
context.move(to:CGPoint(x:615,y:338)); context.addLine(to:CGPoint(x:671,y:285)); context.addLine(to:CGPoint(x:785,y:374)); context.strokePath()
let image=context.makeImage()!
let url=URL(fileURLWithPath:CommandLine.arguments[1])
let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,image,nil); precondition(CGImageDestinationFinalize(dest))
