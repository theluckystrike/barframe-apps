import AppKit
let image = NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
NSColor(calibratedRed:0.035,green:0.20,blue:0.24,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:0,y:0,width:1024,height:1024),xRadius:190,yRadius:190).fill()
for i in 0..<3 {
 NSColor(calibratedWhite:0.65+Double(i)*0.16,alpha:1).setFill()
 NSBezierPath(roundedRect:NSRect(x:220+i*65,y:210+i*65,width:450,height:510),xRadius:35,yRadius:35).fill()
}
NSColor(calibratedRed:0.03,green:0.5,blue:0.53,alpha:1).setFill()
for i in 0..<3 { NSBezierPath(roundedRect:NSRect(x:405,y:620-i*85,width:270,height:27),xRadius:12,yRadius:12).fill() }
NSColor(calibratedRed:0.98,green:0.65,blue:0.23,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:565,y:230,width:140,height:150),xRadius:22,yRadius:22).fill()
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
