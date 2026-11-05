import AppKit
let size=1024
let image=NSImage(size:NSSize(width:size,height:size))
image.lockFocus()
NSColor(calibratedRed:0.035,green:0.13,blue:0.18,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:0,y:0,width:1024,height:1024),xRadius:220,yRadius:220).fill()
for (y,x,w) in [(660,180,530),(440,350,490),(220,180,530)] {
    NSColor(calibratedRed:0.1,green:0.8,blue:0.72,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:x,y:y,width:w,height:110),xRadius:50,yRadius:50).fill()
}
NSColor(calibratedRed:1,green:0.64,blue:0.22,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:480,y:180,width:65,height:640),xRadius:30,yRadius:30).fill()
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
