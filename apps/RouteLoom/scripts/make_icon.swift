import AppKit
import ImageIO
import UniformTypeIdentifiers
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red:0.025,green:0.10,blue:0.14,alpha:1));context.fill(CGRect(x:0,y:0,width:size,height:size))
let bg = CGPath(roundedRect:CGRect(x:35,y:35,width:954,height:954),cornerWidth:210,cornerHeight:210,transform:nil)
context.addPath(bg);context.setFillColor(CGColor(red:0.04,green:0.22,blue:0.27,alpha:1));context.fillPath()
context.setLineCap(.round);context.setLineJoin(.round);context.setLineWidth(66)
let colors = [CGColor(red:0.27,green:0.89,blue:0.78,alpha:1),CGColor(red:0.65,green:0.82,blue:1,alpha:1)]
for (i,y) in [365.0,650.0].enumerated() {
    let path = CGMutablePath();path.move(to:CGPoint(x:210,y:y));path.addCurve(to:CGPoint(x:815,y:y),control1:CGPoint(x:400,y:y+220),control2:CGPoint(x:625,y:y-220))
    context.addPath(path);context.setStrokeColor(colors[i]);context.strokePath()
    for x in [210.0,815] { context.setFillColor(colors[i]);context.fillEllipse(in:CGRect(x:x-56,y:y-56,width:112,height:112)) }
}
context.setFillColor(CGColor(red:1,green:0.74,blue:0.36,alpha:1));context.fillEllipse(in:CGRect(x:466,y:466,width:92,height:92))
let image = context.makeImage()!
let url = URL(fileURLWithPath:CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,image,nil);precondition(CGImageDestinationFinalize(dest))
