import AppKit
import ImageIO
import UniformTypeIdentifiers
let size=1024
let ctx=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red:0.035,green:0.12,blue:0.18,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:size,height:size))
let shield=CGMutablePath(); shield.move(to:CGPoint(x:512,y:860)); shield.addLine(to:CGPoint(x:805,y:744)); shield.addLine(to:CGPoint(x:770,y:420)); shield.addQuadCurve(to:CGPoint(x:512,y:170),control:CGPoint(x:710,y:260)); shield.addQuadCurve(to:CGPoint(x:254,y:420),control:CGPoint(x:314,y:260)); shield.addLine(to:CGPoint(x:219,y:744)); shield.closeSubpath()
ctx.addPath(shield); ctx.setFillColor(CGColor(red:0.18,green:0.77,blue:0.78,alpha:1)); ctx.fillPath()
ctx.setStrokeColor(CGColor(red:0.04,green:0.18,blue:0.25,alpha:1));ctx.setLineWidth(36);ctx.setLineCap(.round)
for y in [460,570,680] { ctx.move(to:CGPoint(x:355,y:y));ctx.addLine(to:CGPoint(x:590,y:y));ctx.strokePath() }
ctx.setFillColor(CGColor(red:1,green:0.76,blue:0.30,alpha:1));ctx.fillEllipse(in:CGRect(x:601,y:340,width:220,height:220))
let dest=CGImageDestinationCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[1]) as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,ctx.makeImage()!,nil);CGImageDestinationFinalize(dest)
