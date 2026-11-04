import AppKit
import SwiftUI
import CoreImage
import MarkShotCore

struct FrameState { var image: CGImage; var marks: [Mark] = [] }
@MainActor final class Document: ObservableObject {
    @Published var timeline: Timeline<FrameState> { didSet { persistChanges() } }
    var onChange: ((Document) throws -> Void)?
    private func persistChanges() {
        do { try onChange?(self) }
        catch { message = "Edits could not be saved to history: \(error.localizedDescription). Export before closing." }
    }
    @Published var tool: Tool = .arrow
    @Published var text = "Look here"
    @Published var message = ""
    let sample: Bool
    var id: UUID
    init(image: CGImage, sample: Bool = false, id: UUID = UUID()) { timeline = Timeline(FrameState(image:image)); self.sample=sample; self.id=id }
    var size: CGSize { CGSize(width:timeline.current.image.width,height:timeline.current.image.height) }
    func add(_ mark: Mark) {
        guard Geometry.valid(mark) else { return }
        message=""
        if mark.tool == .crop {
            guard let rect=Geometry.crop(mark.rect,in:size), let image=rendered()?.cropping(to:rect) else { message="Select a larger crop area.";return }
            timeline.commit(FrameState(image:image))
        } else { var state=timeline.current;state.marks.append(mark);timeline.commit(state) }
    }
    func rendered() -> CGImage? { Raster.render(timeline.current) }
    func png() throws -> Data { guard let image=rendered() else {throw CocoaError(.fileWriteUnknown)}; return try Raster.png(image) }
}
@MainActor enum Raster {
    static func png(_ image: CGImage) throws -> Data {
        let bitmap=NSBitmapImageRep(cgImage:image)
        guard let data=bitmap.representation(using:.png,properties:[:]) else {throw CocoaError(.fileWriteUnknown)}
        return data
    }
    static func render(_ state: FrameState) -> CGImage? {
        let w=state.image.width,h=state.image.height
        guard let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return nil}
        ctx.draw(state.image,in:CGRect(x:0,y:0,width:w,height:h))
        ctx.translateBy(x:0,y:CGFloat(h));ctx.scaleBy(x:1,y:-1)
        let old=NSGraphicsContext.current;NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:true)
        defer {NSGraphicsContext.current=old}
        let stroke=NSColor.systemRed.cgColor
        let width=max(3,CGFloat(min(w,h))/260)
        for mark in state.marks {
            ctx.saveGState();ctx.setStrokeColor(stroke);ctx.setFillColor(stroke);ctx.setLineWidth(width);ctx.setLineCap(.round)
            switch mark.tool {
            case .arrow:
                ctx.move(to:mark.start);ctx.addLine(to:mark.end);ctx.strokePath()
                let points=Geometry.arrowHead(start:mark.start,end:mark.end,length:width*5)
                ctx.beginPath();ctx.addLines(between:points);ctx.strokePath()
            case .rectangle:ctx.stroke(mark.rect)
            case .highlight:ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.35).cgColor);ctx.fill(mark.rect)
            case .text:
                let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.boldSystemFont(ofSize:width*7),.foregroundColor:NSColor.systemRed]
                NSAttributedString(string:mark.text,attributes:attrs).draw(at:mark.start)
            case .step:
                let r=width*5;ctx.fillEllipse(in:CGRect(x:mark.start.x-r,y:mark.start.y-r,width:r*2,height:r*2))
                let string=NSAttributedString(string:String(mark.number),attributes:[.font:NSFont.boldSystemFont(ofSize:width*6),.foregroundColor:NSColor.white])
                let size=string.size();string.draw(at:CGPoint(x:mark.start.x-size.width/2,y:mark.start.y-size.height/2))
            case .blur,.pixelate:
                if let rect=Geometry.crop(mark.rect,in:CGSize(width:w,height:h)),let patch=ctx.makeImage()?.cropping(to:rect) {
                    var result:CGImage? = patch
                    if mark.tool == .blur {
                        let input=CIImage(cgImage:patch)
                        let output=input.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:16.0]).cropped(to:input.extent)
                        result=CIContext().createCGImage(output,from:input.extent)
                    } else {
                        let pw=max(1,patch.width/18),ph=max(1,patch.height/18)
                        if let small=CGContext(data:nil,width:pw,height:ph,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) {
                            small.interpolationQuality = .high;small.draw(patch,in:CGRect(x:0,y:0,width:pw,height:ph));result=small.makeImage()
                        }
                    }
                    if let result {ctx.interpolationQuality = .none;ctx.translateBy(x:rect.minX,y:rect.maxY);ctx.scaleBy(x:1,y:-1);ctx.draw(result,in:CGRect(origin:.zero,size:rect.size))}
                }
            case .crop:break
            }
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}
struct Canvas: NSViewRepresentable {
    @ObservedObject var document: Document
    func makeNSView(context:Context) -> DrawingView {DrawingView(document:document)}
    func updateNSView(_ view:DrawingView,context:Context) {view.document=document;view.needsDisplay=true}
}
@MainActor final class DrawingView:NSView {
    var document:Document
    var start:CGPoint?
    var end:CGPoint?
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(document:Document) {self.document=document;super.init(frame:.zero)}
    required init?(coder:NSCoder) {fatalError()}
    override func draw(_ rect:NSRect) {
        guard let image=document.rendered() else {return}
        NSImage(cgImage:image,size:document.size).draw(in:bounds,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
        if let start,let end {
            NSColor.systemRed.setStroke();let path=NSBezierPath(rect:Geometry.rect(start,end));path.lineWidth=2;path.setLineDash([5,4],count:2,phase:0);path.stroke()
        }
    }
    override func mouseDown(with event:NSEvent) {window?.makeFirstResponder(self);start=convert(event.locationInWindow,from:nil);end=start;needsDisplay=true}
    override func mouseDragged(with event:NSEvent) {end=convert(event.locationInWindow,from:nil);needsDisplay=true}
    override func mouseUp(with event:NSEvent) {
        guard let start else {return}
        let end=convert(event.locationInWindow,from:nil)
        let a=Geometry.imagePoint(start,image:document.size,view:bounds.size),b=Geometry.imagePoint(end,image:document.size,view:bounds.size)
        document.add(Mark(document.tool,a,b,text:document.text,number:Geometry.nextStep(document.timeline.current.marks)))
        self.start=nil;self.end=nil;needsDisplay=true
    }
    override func keyDown(with event:NSEvent) {if event.keyCode==53 {start=nil;end=nil;needsDisplay=true} else {super.keyDown(with:event)}}
}
struct EditorView:View {
    @ObservedObject var document:Document
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Text(document.sample ? "Sample · MarkShot" : "MarkShot").font(.headline)
                Spacer()
                Button("Undo") {document.timeline.undo()}.disabled(document.timeline.undoItems.isEmpty).keyboardShortcut("z")
                Button("Redo") {document.timeline.redo()}.disabled(document.timeline.redoItems.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
                Button("Copy PNG") {model.copy(document)}.keyboardShortcut("c")
                Button("Save PNG…") {model.save(document)}.keyboardShortcut("s")
                Text("Drag PNG out").padding(6).background(.quaternary,in:RoundedRectangle(cornerRadius:6)).onDrag {model.drag(document)}
            }.padding(14)
            HStack {
                ForEach(Tool.allCases,id:\.self) {tool in
                    Button(tool.rawValue.capitalized) {document.tool=tool}.buttonStyle(.bordered).tint(document.tool==tool ? .accentColor:.gray).background(document.tool==tool ? Color.accentColor.opacity(0.25):Color.clear,in:RoundedRectangle(cornerRadius:6))
                }
            }.padding(.horizontal,14).padding(.bottom,12)
            if document.tool == .text {TextField("Text to place (click image)",text:$document.text).textFieldStyle(.roundedBorder).padding(.horizontal,16).padding(.bottom,10)}
            if document.tool == .crop {Text("Drag a rectangle to crop. Undo restores the previous image.").font(.caption).padding(.bottom,8)}
            GeometryReader {proxy in
                let ratio=document.size.width/document.size.height
                let width=min(proxy.size.width-32,(proxy.size.height-32)*ratio)
                Canvas(document:document).frame(width:max(1,width),height:max(1,width/ratio))
                    .background(.white).shadow(radius:8).frame(maxWidth:.infinity,maxHeight:.infinity)
            }.background(Color(nsColor:.underPageBackgroundColor))
            HStack {Text(document.message.isEmpty ? "\(Int(document.size.width)) × \(Int(document.size.height)) · \(document.tool.rawValue.capitalized). Click or drag on the image" : document.message).font(.caption);Spacer();PolicyLinks()}.padding(12)
        }.frame(minWidth:950,minHeight:620)
    }
}
