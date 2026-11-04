import AppKit
import SwiftUI
import ScreenCaptureKit
import MarkShotCore
import Carbon

struct CaptureRecord:Identifiable,Codable,Equatable {let id:UUID;let filename:String;let date:Date;let sample:Bool}
@MainActor final class AppModel:ObservableObject {
    @Published var error=""
    @Published var busy=false
    @Published var records:[CaptureRecord]=[]
    @Published var displays:[SCDisplay]=[]
    @Published var windows:[SCWindow]=[]
    @Published var permissionDenied=false
    @Published var folderName="Choose a save folder"
    @Published var shortcutError=""
    var editorWindow:NSWindow?
    var pickerWindow:NSWindow?
    var document:Document?
    let shortcut=GlobalShortcut()
    let selector=AreaSelector()
    let historyURL:URL
    init(start:Bool=true, historyDirectory:URL?=nil) {
        UserDefaults.standard.register(defaults:["shortcutKey":Int(kVK_ANSI_S),"shortcutOption":true])
        historyURL=historyDirectory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("MarkShot",isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:historyURL,withIntermediateDirectories:true)
            let url=historyURL.appendingPathComponent("history.json")
            if let data=try? Data(contentsOf:url) {records=Array(try JSONDecoder().decode([CaptureRecord].self,from:data).prefix(10)).filter {FileManager.default.fileExists(atPath:historyURL.appendingPathComponent($0.filename).path)}}
        } catch {self.error="History is unavailable: \(error.localizedDescription)"}
        if let data=UserDefaults.standard.data(forKey:"saveFolder"),let url=try? resolve(data) {folderName=url.lastPathComponent}
        if start {shortcut.action = { [weak self] in self?.begin(.area) };configureShortcut()}
    }
    enum Mode {case area,window,screen}
    func configureShortcut() {
        let key=UInt32(UserDefaults.standard.integer(forKey:"shortcutKey")==0 ? kVK_ANSI_S : UserDefaults.standard.integer(forKey:"shortcutKey"))
        let modifiers=UInt32(cmdKey | shiftKey | (UserDefaults.standard.bool(forKey:"shortcutOption") ? optionKey:0))
        let result=shortcut.register(key:key,modifiers:modifiers)
        shortcutError=result==noErr ? "" : "Shortcut unavailable (\(result)). Choose another key or add Option."
    }
    func begin(_ mode:Mode) {
        guard !busy else {return};error="";busy=true
        Task {
            defer {busy=false}
            do {
                guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {permissionDenied=true;error="Screen Recording permission is required. Open System Settings, allow MarkShot, then try again.";return}
                let content=try await CaptureService.content()
                displays=content.displays;windows=content.windows.filter {$0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier && $0.frame.width > 0 && $0.frame.height > 0}
                guard !displays.isEmpty else {error="No capturable display is available.";return}
                permissionDenied=false
                if mode == .window || displays.count > 1 {showPicker(mode)}
                else {await take(mode,display:displays[0],window:nil)}
            } catch {permissionDenied = !CGPreflightScreenCaptureAccess();self.error="Capture failed: \(error.localizedDescription)"}
        }
    }
    func showPicker(_ mode:Mode) {
        let view=CapturePicker(model:self,mode:mode)
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:420),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.title="Choose capture target";w.isReleasedWhenClosed=false;w.contentView=NSHostingView(rootView:view);pickerWindow=w;w.center();w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func choose(_ mode:Mode,display:SCDisplay,window:SCWindow?=nil) {pickerWindow?.close();Task {busy=true;await take(mode,display:display,window:window);busy=false}}
    func take(_ mode:Mode,display:SCDisplay,window:SCWindow?) async {
        do {
            editorWindow?.orderOut(nil)
            let image=try await CaptureService.capture(display:display,window:window)
            if mode == .area {
                let screen=NSScreen.screens.first {($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)==display.displayID} ?? NSScreen.main
                guard let screen else {error="Display is no longer connected.";return}
                selector.select(image:image,screen:screen) { [weak self] rect in
                    guard let self,let rect,let cropped=image.cropping(to:rect) else {return}
                    self.accept(cropped,sample:false)
                }
            } else {accept(image,sample:false)}
        } catch {self.error="Capture failed: \(error.localizedDescription)"}
    }
    static func sampleImage() throws -> CGImage {
        let resources=Bundle.main.resourceURL.flatMap {Bundle(url:$0.appendingPathComponent("MarkShot_MarkShot.bundle"))} ?? Bundle.module
        guard let url=resources.url(forResource:"sample",withExtension:"png",subdirectory:"Resources") else {throw CocoaError(.fileReadNoSuchFile)}
        guard let image=NSImage(contentsOf:url)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {throw CocoaError(.fileReadCorruptFile)}
        return image
    }
    func sample() {do {accept(try Self.sampleImage(),sample:true)} catch {self.error=error.localizedDescription}}
    func accept(_ image:CGImage,sample:Bool,id:UUID=UUID()) {
        let doc=Document(image:image,sample:sample,id:id);document=doc
        connectPersistence(doc)
        do {try retain(doc)} catch {self.error="Capture opened, but history could not be saved: \(error.localizedDescription)"}
        let w=editorWindow ?? NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        w.title=sample ? "MarkShot · Sample" : "MarkShot";w.isReleasedWhenClosed=false;w.contentView=NSHostingView(rootView:EditorView(document:doc,model:self));editorWindow=w;w.center();w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func connectPersistence(_ doc:Document) {
        doc.onChange = { [weak self] changed in try self?.retain(changed) }
    }
    func retain(_ doc:Document) throws {
        let filename="\(doc.id.uuidString).png";try doc.png().write(to:historyURL.appendingPathComponent(filename),options:.atomic)
        let record=CaptureRecord(id:doc.id,filename:filename,date:Date(),sample:doc.sample)
        let old=records;records=Recent.adding(record,to:records.filter {$0.id != doc.id})
        try JSONEncoder().encode(records).write(to:historyURL.appendingPathComponent("history.json"),options:.atomic)
        for entry in old where !records.contains(where:{$0.id==entry.id}) {try? FileManager.default.removeItem(at:historyURL.appendingPathComponent(entry.filename))}
    }
    func reopen(_ record:CaptureRecord) {
        guard let image=NSImage(contentsOf:historyURL.appendingPathComponent(record.filename))?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {error="This history image is unavailable.";return}
        accept(image,sample:record.sample,id:record.id)
    }
    func clearHistory() {
        do {for record in records {try FileManager.default.removeItem(at:historyURL.appendingPathComponent(record.filename))};records=[];try JSONEncoder().encode(records).write(to:historyURL.appendingPathComponent("history.json"),options:.atomic)}
        catch {self.error="Could not clear history: \(error.localizedDescription)"}
    }
    func copy(_ doc:Document) {
        do {let data=try doc.png();let pb=NSPasteboard.general;pb.clearContents();guard pb.setData(data,forType:.png) else {throw CocoaError(.fileWriteUnknown)};try retain(doc);doc.message="PNG copied to clipboard."} catch {doc.message="Copy failed: \(error.localizedDescription)"}
    }
    func resolve(_ data:Data) throws -> URL {
        var stale=false;let url=try URL(resolvingBookmarkData:data,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale)
        if stale {UserDefaults.standard.set(try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil),forKey:"saveFolder")}
        return url
    }
    func chooseFolder() {
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.allowsMultipleSelection=false;panel.prompt="Use folder"
        guard panel.runModal() == .OK,let url=panel.url else {return}
        do {let data=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil);UserDefaults.standard.set(data,forKey:"saveFolder");folderName=url.lastPathComponent}
        catch {self.error="Folder bookmark failed: \(error.localizedDescription)"}
    }
    func save(_ doc:Document) {
        do {
            let data=try doc.png()
            if let bookmark=UserDefaults.standard.data(forKey:"saveFolder") {
                let folder=try resolve(bookmark);let active=folder.startAccessingSecurityScopedResource();defer {if active {folder.stopAccessingSecurityScopedResource()}}
                let url=folder.appendingPathComponent(Geometry.filename(date:Date()));try data.write(to:url,options:.atomic);doc.message="Saved PNG to \(folder.lastPathComponent)."
            } else {
                let panel=NSSavePanel();panel.allowedContentTypes=[.png];panel.nameFieldStringValue=Geometry.filename(date:Date())
                guard panel.runModal() == .OK,let url=panel.url else {return};try data.write(to:url,options:.atomic);doc.message="PNG saved."
            }
            try retain(doc)
        } catch {doc.message="Save failed: \(error.localizedDescription). Choose the folder again in Settings."}
    }
    func drag(_ doc:Document) -> NSItemProvider {
        do {
            try retain(doc)
            let file=historyURL.appendingPathComponent("\(doc.id.uuidString).png")
            let provider=NSItemProvider()
            provider.registerFileRepresentation(forTypeIdentifier:"public.png",fileOptions:[],visibility:.all) {completion in completion(file,false,nil);return nil}
            provider.suggestedName=Geometry.filename(date:Date())
            return provider
        }
        catch {doc.message="Drag failed: \(error.localizedDescription)";return NSItemProvider()}
    }
    func openPrivacySettings() {NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)}
}
