import AppKit
import SwiftUI
import MarkShotCore
import ImageIO
import UniformTypeIdentifiers
@MainActor enum ScreenshotRenderer {
    static func render(to directory:URL) throws {
        _=NSApplication.shared;NSApp.appearance=NSAppearance(named:.darkAqua)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let model=AppModel(start:false)
        for index in 0..<3 {
            let doc=Document(image:try AppModel.sampleImage(),sample:true)
            if index==0 {
                doc.add(Mark(.arrow,CGPoint(x:1050,y:300),CGPoint(x:910,y:450)))
                doc.add(Mark(.rectangle,CGPoint(x:450,y:410),CGPoint(x:1040,y:490)))
                doc.add(Mark(.text,CGPoint(x:700,y:230),.zero,text:"Ready to share"))
            } else if index==1 {
                doc.add(Mark(.highlight,CGPoint(x:465,y:530),CGPoint(x:950,y:570)))
                doc.add(Mark(.step,CGPoint(x:430,y:350),.zero,number:1))
                doc.add(Mark(.step,CGPoint(x:430,y:450),.zero,number:2))
                doc.add(Mark(.step,CGPoint(x:430,y:550),.zero,number:3))
                doc.tool = .step
            } else {
                doc.add(Mark(.pixelate,CGPoint(x:465,y:430),CGPoint(x:830,y:470)))
                doc.add(Mark(.blur,CGPoint(x:465,y:680),CGPoint(x:1040,y:735)))
                doc.tool = .pixelate
            }
            let host=NSHostingView(rootView:EditorView(document:doc,model:model).environment(\.colorScheme,.dark))
            host.frame=CGRect(x:0,y:0,width:1120,height:780)
            let window=NSWindow(contentRect:host.frame,styleMask:.borderless,backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=host;window.display();host.layoutSubtreeIfNeeded()
            guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {throw CocoaError(.fileWriteUnknown)}
            host.cacheDisplay(in:host.bounds,to:bitmap)
            let capture=NSImage(size:host.bounds.size);capture.addRepresentation(bitmap)
            let titles=["Capture and mark your point","Explain each step with clarity","Prepare your screenshot to share"]
            let subtitles=["Area, window or full screen. Add arrows, shapes and text.","Use numbered steps and highlights to guide attention.","Blur or pixelate regions, then copy, save or drag your PNG."]
            let renderer=ImageRenderer(content:StoreShot(capture:capture,title:titles[index],subtitle:subtitles[index]).environment(\.colorScheme,.dark))
            renderer.proposedSize=ProposedViewSize(width:1440,height:900);renderer.scale=2;renderer.isOpaque=true
            guard let image=renderer.cgImage,let ctx=CGContext(data:nil,width:2880,height:1800,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {throw CocoaError(.fileWriteUnknown)}
            ctx.setFillColor(NSColor.black.cgColor);ctx.fill(CGRect(x:0,y:0,width:2880,height:1800));ctx.draw(image,in:CGRect(x:0,y:0,width:2880,height:1800))
            guard let result=ctx.makeImage(),let destination=CGImageDestinationCreateWithURL(directory.appendingPathComponent("0\(index+1)-markshot.png") as CFURL,UTType.png.identifier as CFString,1,nil) else {throw CocoaError(.fileWriteUnknown)}
            CGImageDestinationAddImage(destination,result,nil);guard CGImageDestinationFinalize(destination) else {throw CocoaError(.fileWriteUnknown)}
            window.close()
        }
    }
}
struct StoreShot:View {
    let capture:NSImage;let title:String;let subtitle:String
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {Text("MarkShot").font(.system(size:18,weight:.semibold)).foregroundStyle(.cyan);Spacer();Text("Sample · example workspace").font(.system(size:14)).foregroundStyle(.white.opacity(0.6))}
            Text(title).font(.system(size:34,weight:.semibold)).foregroundStyle(.white)
            Text(subtitle).font(.system(size:18)).foregroundStyle(.white.opacity(0.7))
            Image(nsImage:capture).resizable().frame(width:1120,height:780).clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.15)))
        }.frame(width:1120).frame(width:1440,height:900).background(LinearGradient(colors:[Color(red:0.035,green:0.08,blue:0.14),Color(red:0.065,green:0.16,blue:0.20)],startPoint:.topLeading,endPoint:.bottomTrailing))
    }
}
