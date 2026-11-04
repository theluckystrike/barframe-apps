import AppKit
import Foundation
import MASKit
import MarkShotCore
@MainActor enum SelfTest {
    static func run()->Int32 {
        _=NSApplication.shared
        var checks:[SmokeCheck]=[]
        do {
            let image=try AppModel.sampleImage()
            checks.append(SmokeCheck(name:"bundled-sample-decode",pass:image.width>0 && image.height>0,detail:"\(image.width)x\(image.height)"))
            let doc=Document(image:image,sample:true)
            doc.add(Mark(.arrow,CGPoint(x:300,y:100),CGPoint(x:100,y:300)))
            doc.add(Mark(.rectangle,CGPoint(x:100,y:100),CGPoint(x:300,y:200)))
            doc.add(Mark(.pixelate,CGPoint(x:400,y:200),CGPoint(x:600,y:400)))
            let data=try doc.png();let rep=NSBitmapImageRep(data:data)
            checks.append(SmokeCheck(name:"annotation-png-roundtrip",pass:rep?.pixelsWide==image.width && rep?.pixelsHigh==image.height && data != (try? Raster.png(image)),detail:"PNG bytes=\(data.count); annotations=\(doc.timeline.current.marks.count)"))
            let pb=NSPasteboard.withUniqueName();defer {pb.releaseGlobally()}
            let write=pb.setData(data,forType:.png)
            checks.append(SmokeCheck(name:"png-clipboard-roundtrip",pass:write && pb.data(forType:.png)==data,detail:"PNG pasteboard roundtrip=\(write)"))
            let root=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("MarkShot-smoke-\(UUID().uuidString)",isDirectory:true)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
            let model=AppModel(start:false,historyDirectory:root.appendingPathComponent("history"))
            let retained=Document(image:image,sample:true)
            model.connectPersistence(retained)
            let original=try retained.png()
            retained.add(Mark(.rectangle,CGPoint(x:40,y:40),CGPoint(x:400,y:300)))
            let edited=try retained.png()
            let historyFile=model.historyURL.appendingPathComponent("\(retained.id.uuidString).png")
            let afterEdit=try Data(contentsOf:historyFile)
            retained.timeline.undo()
            let afterUndo=try Data(contentsOf:historyFile)
            retained.timeline.redo()
            let afterRedo=try Data(contentsOf:historyFile)
            retained.add(Mark(.crop,CGPoint(x:10,y:10),CGPoint(x:110,y:110)))
            let afterCrop=NSBitmapImageRep(data:try Data(contentsOf:historyFile))
            retained.timeline.undo()
            let restarted=AppModel(start:false,historyDirectory:model.historyURL)
            let reopened=try Data(contentsOf:historyFile)
            checks.append(SmokeCheck(name:"P3-edit-history-survives-restart",pass:afterEdit==edited && edited != original && afterUndo==original && afterRedo==edited && afterCrop?.pixelsWide==100 && reopened==edited && restarted.records.first?.id==retained.id,detail:"Annotation, undo, redo and crop persist without export; fresh model reads history"))
            let failure=Document(image:image,sample:true)
            failure.onChange = {_ in throw CocoaError(.fileWriteNoPermission)}
            failure.add(Mark(.step,CGPoint(x:50,y:50),.zero,number:1))
            checks.append(SmokeCheck(name:"P3-persistence-failure-visible",pass:failure.message.contains("Export before closing"),detail:"A write error produces an actionable editor message"))
            let policy=try LocalPolicy.text("privacy")
            let support=try LocalPolicy.text("support")
            checks.append(SmokeCheck(name:"P2-bundled-policy-retention-deletion",pass:policy.contains("last ten") && policy.contains("Clear") && policy.contains("bookmark") && policy.contains("Finder") && !support.isEmpty,detail:"Bundled policy describes retention, deletion, bookmarks and exported files; support bundled"))
            checks.append(SmokeCheck(name:"policy-placeholder-fallback",pass:LocalPolicy.webURL("https://{DOMAIN}/privacy/")==nil && LocalPolicy.webURL("https://{BRAND}/support/")==nil && LocalPolicy.webURL("https://barframe.com/apps/markshot/privacy/") != nil,detail:"Provisional URLs excluded; finalized HTTPS URL available alongside local text"))
            let file=root.appendingPathComponent("sample.png");try data.write(to:file,options:.atomic)
            let bookmark=try root.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
            var stale=false;let restored=try URL(resolvingBookmarkData:bookmark,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale)
            let active=restored.startAccessingSecurityScopedResource();defer {if active {restored.stopAccessingSecurityScopedResource()}}
            let readback=try Data(contentsOf:restored.appendingPathComponent("sample.png"))
            checks.append(SmokeCheck(name:"container-save-bookmark",pass: !stale && readback==data,detail:"Container folder bookmark and PNG save roundtrip"))
            doc.add(Mark(.crop,CGPoint(x:10,y:10),CGPoint(x:110,y:110)))
            let cropped=doc.size;doc.timeline.undo()
            checks.append(SmokeCheck(name:"crop-undo",pass:cropped==CGSize(width:100,height:100) && doc.size==CGSize(width:image.width,height:image.height),detail:"Crop=\(cropped); undo=\(doc.size)"))
        } catch {checks.append(SmokeCheck(name:"runtime-error",pass:false,detail:error.localizedDescription))}
        let report=SmokeReport(app:"MarkShot",bundleID:Bundle.main.bundleIdentifier ?? "",version:"1.0.0",checks:checks)
        do {try report.write()} catch {return 1}
        return report.sandboxed && report.pass ? 0:1
    }
}
