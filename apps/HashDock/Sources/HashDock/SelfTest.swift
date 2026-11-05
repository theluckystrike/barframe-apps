import Foundation
import AppKit
import MASKit
import HashDockCore
@MainActor enum SelfTest {
    static func external(reopen: Bool) -> Int32 {
        _ = NSApplication.shared; NSApp.activate(ignoringOtherApps:true)
        let file=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/HashDock/ExternalTest/state.json")
        let model=Model(storage:file)
        do {
            guard reopen else { throw ScanError.unavailable }
            guard let recipient=model.job.recipients.first else { throw ScanError.unavailable }
            let source=try model.resolve(model.job.source,path:nil); let destination=try model.resolve(recipient.bookmark,path:nil)
            let sourceAccess=source.startAccessingSecurityScopedResource(); let destAccess=destination.startAccessingSecurityScopedResource()
            defer { if sourceAccess { source.stopAccessingSecurityScopedResource() }; if destAccess { destination.stopAccessingSecurityScopedResource() } }
            let frozen=try Engine.freeze(source); let result=Engine.verify(destination,manifest:frozen)
            model.job.manifest=frozen; model.job.recipients[0].result=result; model.save()
            let report=SmokeReport(app:"HashDock",bundleID:"com.michaellip.hashdock",version:"1.0.0",checks:[SmokeCheck(name:reopen ? "External bookmark after process restart" : "External Open Panel grants",pass:sourceAccess && destAccess && result.status == "Verified" && result.verified > 0,detail:source.path + " · " + result.status)])
            try report.write(); return report.pass ? 0 : 1
        } catch {
            try? SmokeReport(app:"HashDock",bundleID:"com.michaellip.hashdock",version:"1.0.0",checks:[SmokeCheck(name:"External selection",pass:false,detail:error.localizedDescription)]).write(); return 1
        }
    }
    static func run() -> Int32 {
        let defaults=UserDefaults.standard; let domain=Bundle.main.bundleIdentifier ?? "com.michaellip.hashdock"
        let preferences=defaults.persistentDomain(forName:domain) ?? [:]
        defer {
            HotKey.shared.register((preferences["hotkey"] as? NSNumber)?.uint32Value ?? 4)
            defaults.setPersistentDomain(preferences,forName:domain)
        }
        defaults.set(false,forKey:"extraFails")
        let m=Model(); m.switchSample(true)
        var checks=[SmokeCheck(name:"Sample matrix",pass:m.job.recipients.map {$0.result?.status} == ["Verified","Findings","Offline"],detail:"Independent matching missing and offline recipients")]
        do {
            let root=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/HashDock/Smoke")
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            try Data("sandbox fixture".utf8).write(to:root.appendingPathComponent("Input.txt"))
            let frozen=try Engine.freeze(root); let result=Engine.verify(root,manifest:frozen)
            checks.append(SmokeCheck(name:"Real file API read",pass:result.status == "Verified" && result.verified == 1,detail:"Streaming digest in signed sandbox"))
            let url=root.appendingPathComponent("state.json"); try JSONEncoder().encode(m.job).write(to:url,options:.atomic)
            let restored=try JSONDecoder().decode(Job.self,from:Data(contentsOf:url)); try FileManager.default.removeItem(at:url)
            checks.append(SmokeCheck(name:"Persistence reopen",pass:restored.manifest?.id == m.job.manifest?.id && restored.recipients.count == 3,detail:"Encoded state restored from container disk"))
            let modelFile=root.appendingPathComponent("model.json")
            let live=Model(storage:modelFile); live.job=restored; live.save()
            let reopened=Model(storage:modelFile)
            checks.append(SmokeCheck(name:"App model restart preserves results",pass:reopened.job.recipients.first?.result?.status == "Verified",detail:"Loading saved preferences does not invalidate unchanged verification policy"))
            live.switchSample(true); live.extraFails=true; live.switchSample(false)
            checks.append(SmokeCheck(name:"Sample policy isolated",pass:!live.extraFails && live.job.recipients.first?.result?.status == "Verified",detail:"Sample policy never changes Live defaults or results"))
            let first=live.library.pinned; live.newJob(); live.job.name="Second"; live.save(); live.pin(first)
            checks.append(SmokeCheck(name:"Pinned jobs retain receipts",pass:live.library.jobs.count == 2 && live.job.manifest?.id == restored.manifest?.id,detail:"Changing jobs preserves independent state"))
            live.job.recipients.removeAll(); var clean=Recipient(alias:"Extras"); var value=Verification(revision:restored.manifest!.id); value.extra=["extra"]; clean.result=value; live.job.recipients=[clean]
            checks.append(SmokeCheck(name:"Menu agrees with extras",pass:live.menuTitle.contains("All checked") && live.symbol == "externaldrive.badge.checkmark",detail:"One shared success rule"))
            let mounts=FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:nil,options:[])?.map(\.path)
            checks.append(SmokeCheck(name:"Sandbox volume presence",pass:mounts?.contains("/") == true,detail:"Mounted-volume URLs are available without folder content access"))
            var offline=Recipient(alias:"Disconnected",bookmark:Data([0,1,2])); offline.savedPath="/Volumes/HashDockDisconnectedA6/Copy"
            live.job.recipients.append(offline); live.verify(offline.id)
            checks.append(SmokeCheck(name:"Disconnected bookmark is offline",pass:live.job.recipients.last?.result?.offline == true && live.job.recipients.last?.staleReason == nil,detail:"Missing volume cannot be shown as a stale permission"))
            live.removeRecipient(offline.id)
            live.removeRecipient(clean.id)
            checks.append(SmokeCheck(name:"Remove recipient updates menu",pass:live.job.recipients.isEmpty && live.menuTitle.contains("No inputs"),detail:"Removing wrong picks does not wipe job"))
            HotKey.shared.register(2)
            let clear=Model(storage:root.appendingPathComponent("Clear/state.json")); clear.forget()
            checks.append(SmokeCheck(name:"Forget restores shortcut",pass:HotKey.shared.key == 4,detail:"Default public hotkey registered after reset"))
            try FileManager.default.removeItem(at:modelFile)
            var job=restored; job.refresh(frozen)
            checks.append(SmokeCheck(name:"Revision invalidation",pass:job.recipients.allSatisfy {$0.result == nil},detail:"Every old recipient result cleared"))
        } catch { checks.append(SmokeCheck(name:"File operations",pass:false,detail:error.localizedDescription)) }
        m.token.cancel(); m.verifyAll()
        let deadline=Date().addingTimeInterval(10)
        while m.busy && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
        checks.append(SmokeCheck(name:"Verify all after cancellation",pass:!m.busy && m.job.recipients.map {$0.result?.status} == ["Verified","Findings","Offline"],detail:"Every recipient gets an independent fresh result"))
        let report=SmokeReport(app:"HashDock",bundleID:"com.michaellip.hashdock",version:"1.0.0",checks:checks)
        do { try report.write() } catch { return 1 }; return report.pass ? 0 : 1
    }
}
