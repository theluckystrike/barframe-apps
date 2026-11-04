import AppKit
import ImageIO
import UniformTypeIdentifiers
let root=URL(fileURLWithPath:CommandLine.arguments[1])
func image(_ width:Int,_ height:Int,_ draw:(CGContext)->Void)->CGImage {
    let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    let old=NSGraphicsContext.current;NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false);draw(ctx);NSGraphicsContext.current=old
    return ctx.makeImage()!
}
func write(_ image:CGImage,_ path:String) {
    let url=root.appendingPathComponent(path);try! FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
    let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!;CGImageDestinationAddImage(dest,image,nil);assert(CGImageDestinationFinalize(dest))
}
func text(_ string:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:NSColor = .white) {
    NSAttributedString(string:string,attributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:color]).draw(at:CGPoint(x:x,y:y))
}
write(image(1024,1024) {ctx in
    ctx.setFillColor(NSColor(calibratedRed:0.03,green:0.13,blue:0.2,alpha:1).cgColor);ctx.fill(CGRect(x:0,y:0,width:1024,height:1024))
    ctx.setFillColor(NSColor(calibratedRed:0.08,green:0.27,blue:0.34,alpha:1).cgColor);ctx.addPath(CGPath(roundedRect:CGRect(x:120,y:120,width:784,height:784),cornerWidth:150,cornerHeight:150,transform:nil));ctx.fillPath()
    ctx.setStrokeColor(NSColor.white.cgColor);ctx.setLineWidth(38);ctx.setLineCap(.round)
    for (x,y,dx,dy) in [(260.0,700.0,140.0,0.0),(260.0,700.0,0.0,-140.0),(764.0,324.0,-140.0,0.0),(764.0,324.0,0.0,140.0)] {ctx.move(to:CGPoint(x:x,y:y));ctx.addLine(to:CGPoint(x:x+dx,y:y+dy));ctx.strokePath()}
    ctx.setStrokeColor(NSColor(calibratedRed:0.23,green:0.9,blue:0.88,alpha:1).cgColor);ctx.setLineWidth(56)
    ctx.move(to:CGPoint(x:350,y:365));ctx.addLine(to:CGPoint(x:680,y:670));ctx.strokePath()
    ctx.move(to:CGPoint(x:525,y:668));ctx.addLine(to:CGPoint(x:680,y:670));ctx.addLine(to:CGPoint(x:678,y:515));ctx.strokePath()
},"assets/AppIcon-1024.png")
write(image(1400,900) {ctx in
    ctx.setFillColor(NSColor(calibratedRed:0.93,green:0.95,blue:0.98,alpha:1).cgColor);ctx.fill(CGRect(x:0,y:0,width:1400,height:900))
    ctx.setFillColor(NSColor(calibratedRed:0.06,green:0.12,blue:0.2,alpha:1).cgColor);ctx.fill(CGRect(x:0,y:0,width:330,height:900))
    text("Sample workspace",38,820,27);text("PROJECT NOTES",38,750,15,.systemTeal)
    text("Overview",38,680,23);text("Design review",38,620,23);text("Release checklist",38,560,23)
    text("Example content",38,70,18,.lightGray)
    text("Release checklist",410,790,38,.black);text("A sample board for clear feedback",410,735,23,.darkGray)
    for (i,title) in ["Review the draft","Confirm the details","Share the update"].enumerated() {
        let y=CGFloat(510-i*100)
        ctx.setFillColor(NSColor.white.cgColor);ctx.addPath(CGPath(roundedRect:CGRect(x:410,y:y,width:890,height:80),cornerWidth:14,cornerHeight:14,transform:nil));ctx.fillPath()
        text(title,470,y+26,25,.black)
        if i==0 {text("In progress",1070,y+27,19,.systemBlue)}
    }
    ctx.setFillColor(NSColor.white.cgColor);ctx.addPath(CGPath(roundedRect:CGRect(x:410,y:135,width:890,height:110),cornerWidth:14,cornerHeight:14,transform:nil));ctx.fillPath()
    text("Example note for annotation",470,190,24,.darkGray);text("All content in this image is synthetic.",470,150,20,.gray)
},"Sources/MarkShot/Resources/sample.png")
print("Custom icon and bundled sample created")
