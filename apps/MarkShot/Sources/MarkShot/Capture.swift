import AppKit
import ScreenCaptureKit
import SwiftUI
import Carbon
import MarkShotCore

@MainActor final class CaptureService {
    static func content() async throws -> SCShareableContent {try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)}
    static func capture(display:SCDisplay,window:SCWindow? = nil) async throws -> CGImage {
        let filter:SCContentFilter
        if let window {filter=SCContentFilter(desktopIndependentWindow:window)}
        else {
            let apps = (try await content()).applications.filter {$0.bundleIdentifier == Bundle.main.bundleIdentifier}
            filter=SCContentFilter(display:display,excludingApplications:apps,exceptingWindows:[])
        }
        let configuration=SCStreamConfiguration()
        configuration.showsCursor=false
        let scale=filter.pointPixelScale
        configuration.width=max(1,Int(filter.contentRect.width*CGFloat(scale)))
        configuration.height=max(1,Int(filter.contentRect.height*CGFloat(scale)))
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
    }
}
@MainActor final class SelectionWindow:NSWindow {
    override var canBecomeKey:Bool {true}
    override var canBecomeMain:Bool {true}
}
@MainActor final class AreaSelector {
    var window:NSWindow?
    func select(image:CGImage,screen:NSScreen,completion:@escaping(CGRect?)->Void) {
        let w=SelectionWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
        w.level = .screenSaver;w.isOpaque=true;w.backgroundColor = .black;w.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let view=SelectionView(image:image,size:screen.frame.size) { [weak self] rect in self?.window?.orderOut(nil);self?.window=nil;completion(rect) }
        w.contentView=view;window=w;w.makeKeyAndOrderFront(nil);w.makeFirstResponder(view);NSApp.activate(ignoringOtherApps:true)
    }
}
@MainActor final class SelectionView:NSView {
    let image:CGImage
    let done:(CGRect?)->Void
    var start:CGPoint?
    var end:CGPoint?
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(image:CGImage,size:CGSize,done:@escaping(CGRect?)->Void) {self.image=image;self.done=done;super.init(frame:CGRect(origin:.zero,size:size))}
    required init?(coder:NSCoder) {fatalError()}
    override func draw(_ dirtyRect:NSRect) {
        NSImage(cgImage:image,size:bounds.size).draw(in:bounds,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
        NSColor.black.withAlphaComponent(0.3).setFill();bounds.fill()
        if let start,let end {NSColor.white.setStroke();let path=NSBezierPath(rect:Geometry.rect(start,end));path.lineWidth=2;path.stroke()}
        NSAttributedString(string:"Drag to select an area · Escape to cancel",attributes:[.font:NSFont.boldSystemFont(ofSize:20),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black]).draw(at:CGPoint(x:24,y:24))
    }
    override func mouseDown(with event:NSEvent) {start=convert(event.locationInWindow,from:nil);end=start;needsDisplay=true}
    override func mouseDragged(with event:NSEvent) {end=convert(event.locationInWindow,from:nil);needsDisplay=true}
    override func mouseUp(with event:NSEvent) {
        guard let start else {return};let end=convert(event.locationInWindow,from:nil)
        let size=CGSize(width:image.width,height:image.height)
        let rect=Geometry.rect(Geometry.imagePoint(start,image:size,view:bounds.size),Geometry.imagePoint(end,image:size,view:bounds.size))
        done(Geometry.crop(rect,in:size))
    }
    override func keyDown(with event:NSEvent) {if event.keyCode==53 {done(nil)} else {super.keyDown(with:event)}}
}
@MainActor final class GlobalShortcut {
    var reference:EventHotKeyRef?
    var handler:EventHandlerRef?
    var action:(()->Void)?
    init() {
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), {_,_,context in
            guard let context else {return OSStatus(eventNotHandledErr)}
            let shortcut=Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {shortcut.action?()};return noErr
        },1,&type,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    deinit {
        if let reference {UnregisterEventHotKey(reference)}
        if let handler {RemoveEventHandler(handler)}
    }
    func register(key:UInt32,modifiers:UInt32) -> OSStatus {
        if let reference {UnregisterEventHotKey(reference);self.reference=nil}
        return RegisterEventHotKey(key,modifiers,EventHotKeyID(signature:0x4D534854,id:1),GetApplicationEventTarget(),0,&reference)
    }
}
