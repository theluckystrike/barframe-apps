import Testing
import Foundation
@testable import HashDockCore
func fixture() throws -> URL { let u=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true); return u }
func put(_ root: URL,_ name: String,_ data: String) throws { try Data(data.utf8).write(to:root.appendingPathComponent(name)) }
@Test func matching() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","abc"); let m=try Engine.freeze(r); #expect(Engine.verify(r,manifest:m).status == "Verified") }
@Test func missing() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","abc"); let m=try Engine.freeze(r); try FileManager.default.removeItem(at:r.appendingPathComponent("a")); #expect(Engine.verify(r,manifest:m).missing == ["a"]) }
@Test func sameSizeMismatch() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","abc"); let m=try Engine.freeze(r); try put(r,"a","xyz"); #expect(Engine.verify(r,manifest:m).changed == ["a"]) }
@Test func extraWarns() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"source","abc"); let m=try Engine.freeze(r); try put(r,"extra","x"); #expect(Engine.verify(r,manifest:m).status == "Verified with extras") }
@Test func extraFails() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"source","abc"); let m=try Engine.freeze(r); try put(r,"extra","x"); #expect(Engine.verify(r,manifest:m,extraFails:true).status == "Findings") }
@Test func offline() { let m=Manifest(entries:[]); #expect(Engine.verify(URL(fileURLWithPath:"/nonexistent/HashDock"),manifest:m).status == "Offline") }
@Test func cancelFreeze() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; let t=Cancellation(); t.cancel(); #expect(throws:ScanError.self) { try Engine.freeze(r,token:t) } }
@Test func cancelVerify() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; let t=Cancellation(); t.cancel(); #expect(Engine.verify(r,manifest:Manifest(entries:[]),token:t).status == "Incomplete") }
@Test func changesDuringRead() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","abc"); #expect(throws:ScanError.self) { try Engine.hash(r.appendingPathComponent("a"),chunk:{try? put(r,"a","different")}) } }
@Test func knownSHA() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","abc"); #expect(try Engine.hash(r.appendingPathComponent("a")).digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") }
@Test func byteCount() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","abc"); #expect(try Engine.hash(r.appendingPathComponent("a")).bytes == 3) }
@Test func emptyFile() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a",""); #expect(try Engine.hash(r.appendingPathComponent("a")).bytes == 0) }
@Test func symlinkExcluded() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try FileManager.default.createSymbolicLink(atPath:r.appendingPathComponent("link").path,withDestinationPath:"/etc/hosts"); try put(r,"a","abc"); let m=try Engine.freeze(r); #expect(m.entries.count == 1); #expect(m.warnings == ["link"]) }
@Test func symlinkIncomplete() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try FileManager.default.createSymbolicLink(atPath:r.appendingPathComponent("link").path,withDestinationPath:"/etc/hosts"); #expect(Engine.verify(r,manifest:Manifest(entries:[])).status == "Incomplete") }
@Test func rejectRootSymlink() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; let link=r.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:r); #expect(throws:ScanError.self) { try Engine.freeze(link) } }
@Test func relativeTraversal() { #expect(!Engine.safe("../private")); #expect(!Engine.safe("folder/../private")) }
@Test func absolutePath() { #expect(!Engine.safe("/etc/hosts")); #expect(!Engine.safe("")); #expect(Engine.safe("folder/file.txt")) }
@Test func refreshInvalidatesAll() { var j=Job(); var r=Recipient(alias:"One"); r.result=Verification(revision:"old"); j.recipients=[r,r]; j.refresh(Manifest(entries:[])); #expect(j.recipients.allSatisfy {$0.result == nil}) }
@Test func revisionsAreUnique() { #expect(Manifest(entries:[]).id != Manifest(entries:[]).id) }
@Test func staleVerification() { #expect(!Verification(revision:"old").current(Manifest(entries:[]))) }
@Test func persistentRoundTrip() throws { var j=Job(); j.name="Round trip"; j.refresh(Manifest(entries:[])); j.recipients=[Recipient(alias:"Studio",bookmark:Data([1,2,3]))]; let other=try JSONDecoder().decode(Job.self,from:JSONEncoder().encode(j)); #expect(other.name == j.name); #expect(other.manifest?.id == j.manifest?.id); #expect(other.recipients[0].bookmark == Data([1,2,3])) }
@Test func corruptState() { #expect(throws:(any Error).self) { try JSONDecoder().decode(Job.self,from:Data("invalid".utf8)) } }
@Test func sampleReceipt() { #expect(Job().receipt(sample:true,filenames:false).hasPrefix("Sample")) }
@Test func liveReceipt() { #expect(!Job().receipt(sample:false,filenames:false).hasPrefix("Sample")) }
@Test func receiptRedaction() { var j=Job(); let m=Manifest(entries:[]); j.manifest=m; var r=Recipient(alias:"Studio"); var v=Verification(revision:m.id); v.missing=["Secret.txt"]; r.result=v; j.recipients=[r]; #expect(!j.receipt(sample:false,filenames:false).contains("Secret.txt")); #expect(j.receipt(sample:false,filenames:true).contains("Secret.txt")) }
@Test func independentRecipients() { var j=Job(); let m=Manifest(entries:[]); j.manifest=m; var r=Recipient(alias:"A"); r.result=Verification(revision:m.id); j.recipients=[r,Recipient(alias:"B")]; #expect(j.recipients[1].result == nil) }
@Test func nestedFiles() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try FileManager.default.createDirectory(at:r.appendingPathComponent("nested"),withIntermediateDirectories:true); try put(r,"nested/a","abc"); #expect(try Engine.freeze(r).entries[0].path == "nested/a") }
@Test func chunkCancellation() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a",String(repeating:"x",count:2097152)); let t=Cancellation(); #expect(throws:ScanError.self) { try Engine.hash(r.appendingPathComponent("a"),token:t,chunk:{t.cancel()}) } }

@Test func cancelEnumeration() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","x"); let t=Cancellation(); t.cancel(); #expect(throws:ScanError.self) { try Engine.files(r,token:t) } }
@Test func directorySymlinkExcluded() throws { let r=try fixture(); let outside=try fixture(); defer { try? FileManager.default.removeItem(at:r); try? FileManager.default.removeItem(at:outside) }; try put(outside,"secret","not in root"); try FileManager.default.createSymbolicLink(at:r.appendingPathComponent("linked"),withDestinationURL:outside); try put(r,"a","abc"); let m=try Engine.freeze(r); #expect(m.entries.count == 1); #expect(m.warnings == ["linked"]) }
@Test func maliciousManifestPath() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; let m=Manifest(entries:[Entry(path:"../outside",bytes:0,digest:"")]); #expect(Engine.verify(r,manifest:m).status == "Incomplete") }

@Test func staleReceiptDoesNotClaimVerified() { var j=Job(); let m=Manifest(entries:[]); j.manifest=m; var r=Recipient(alias:"Studio"); r.result=Verification(revision:m.id); r.staleReason="Permission stale"; j.recipients=[r]; #expect(!j.receipt(sample:false,filenames:false).contains("Verified")); #expect(j.recipients[0].result != nil) }

@Test func finderMetadataIgnoredWithWarnings() throws {
    let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }
    try put(r,"payload","abc")
    for name in [".DS_Store","._payload","Icon\r"] { try put(r,name,"metadata") }
    for name in [".Spotlight-V100",".fseventsd",".Trashes"] { try FileManager.default.createDirectory(at:r.appendingPathComponent(name),withIntermediateDirectories:true); try put(r,name+"/hidden","x") }
    let m=try Engine.freeze(r); #expect(m.entries.map(\.path) == ["payload"]); #expect(m.warnings.count == 6)
    let v=Engine.verify(r,manifest:m,extraFails:true); #expect(v.status == "Verified"); #expect(v.warnings?.count == 6)
}
@Test func unreadableFolderContinues() throws {
    let r=try fixture(); let blocked=r.appendingPathComponent("protected"); defer { try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:blocked.path); try? FileManager.default.removeItem(at:r) }
    try put(r,"readable","abc"); try FileManager.default.createDirectory(at:blocked,withIntermediateDirectories:true); try put(r,"protected/secret","x"); try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:blocked.path)
    let m=try Engine.freeze(r); #expect(m.entries.map(\.path) == ["readable"]); #expect(m.warnings.contains { $0.contains("protected") }); #expect(Engine.verify(r,manifest:m).status == "Incomplete")
}
@Test func failedSourceFileNamedAndScanContinues() throws {
    let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","a"); try put(r,"b","b")
    let m=try Engine.freeze(r,progress:{ value in if value.hasSuffix(" · a") { try? FileManager.default.removeItem(at:r.appendingPathComponent("a")) } })
    #expect(m.entries.map(\.path) == ["b"]); #expect(m.warnings.contains("Unreadable · a")); #expect(Engine.verify(r,manifest:m).status == "Incomplete")
}
@Test func refuseEmptyManifest() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; #expect(throws:ScanError.emptyManifest) { try Engine.freeze(r) }; #expect(Engine.verify(r,manifest:Manifest(entries:[])).status == "Incomplete") }
@Test func removeOnlyChosenRecipient() { var j=Job(); let a=Recipient(alias:"A"); let b=Recipient(alias:"B"); j.recipients=[a,b]; j.removeRecipient(a.id); #expect(j.recipients.map(\.id) == [b.id]) }
@Test func multipleJobsPersist() throws { var library=JobLibrary(); let first=library.pinned; library.jobs[first]?.name="First"; library.create(); library.jobs[library.pinned]?.name="Second"; let loaded=try JSONDecoder().decode(JobLibrary.self,from:JSONEncoder().encode(library)); #expect(loaded.jobs.count == 2); #expect(loaded.jobs[first]?.name == "First"); #expect(loaded.jobs[loaded.pinned]?.name == "Second") }
@Test func policyInvalidatesEveryJob() { var library=JobLibrary(); var r=Recipient(alias:"A"); r.result=Verification(revision:"old"); library.jobs[library.pinned]?.recipients=[r]; library.create(); library.jobs[library.pinned]?.recipients=[r]; library.invalidatePolicy(true); #expect(library.jobs.values.allSatisfy { $0.recipients.first?.result == nil }) }
@Test func completedTimestampAndCancellation() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","abc"); let m=try Engine.freeze(r); let v=Engine.verify(r,manifest:m); #expect(v.completed != nil); #expect(v.completed! >= v.date); let token=Cancellation(); token.cancel(); let interrupted=Engine.verify(r,manifest:m,token:token); #expect(interrupted.completed == nil); #expect(interrupted.interrupted) }
@Test func progressIncludesFileCoverage() throws { let r=try fixture(); defer { try? FileManager.default.removeItem(at:r) }; try put(r,"a","abc"); var messages:[String]=[]; let m=try Engine.freeze(r,progress:{messages.append($0)}); _=Engine.verify(r,manifest:m,progress:{messages.append($0)}); #expect(messages == ["1 of 1 files · a","1 of 1 files · a"]) }
@Test func spanishReceiptStates() { var j=Job(); j.name="Entrega"; let m=Manifest(entries:[]); j.manifest=m; var r=Recipient(alias:"Cliente"); var v=Verification(revision:m.id); v.missing=["a"]; r.result=v; j.recipients=[r]; let text=j.receipt(sample:true,filenames:true,spanish:true); #expect(text.contains("Diferencias")); #expect(text.contains("Ausente a")); #expect(!text.contains("missing")); #expect(!text.contains("Completed")) }

@Test func provisionalPolicyUsesLocalPage() { #expect(PolicyLink.webURL("https://{DOMAIN}/apps/hashdock/privacy/") == nil); #expect(PolicyLink.webURL(nil) == nil); #expect(PolicyLink.webURL("https://barframe.com/apps/hashdock/support/")?.host == "barframe.com") }

@Test func allUnreadableSourceNamesFailures() throws { let r=try fixture(); defer { try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:r.appendingPathComponent("locked.txt").path); try? FileManager.default.removeItem(at:r) }; try put(r,"locked.txt","x"); try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:r.appendingPathComponent("locked.txt").path); do { _=try Engine.freeze(r); Issue.record("Unreadable-only source was accepted") } catch let error as EmptySourceFailure { #expect(error.warnings == ["Unreadable · locked.txt"]) } }

@Test func policyLinkRequiresProductRoute() { #expect(PolicyLink.webURL("https://barframe.com/apps/hashdock/privacy/",path:"/apps/hashdock/privacy/") != nil); #expect(PolicyLink.webURL("https://barframe.com/other/privacy/",path:"/apps/hashdock/privacy/") == nil) }

@Test func spanishReceiptLocalizesFailureReasons() { var job=Job(); let manifest=Manifest(entries:[]); job.manifest=manifest; var r=Recipient(alias:"Cliente"); var v=Verification(revision:manifest.id); v.unreadable=["Folder access denied. Choose again.","Unreadable · locked.txt"]; v.warnings=["Skipped metadata · .DS_Store"]; r.result=v; job.recipients=[r]; let receipt=job.receipt(sample:true,filenames:true,spanish:true); #expect(receipt.contains("Acceso a la carpeta denegado")); #expect(receipt.contains("Ilegible · locked.txt")); #expect(receipt.contains("Metadatos omitidos")); #expect(!receipt.contains("Folder access")); #expect(!receipt.contains("Unreadable")); #expect(!receipt.contains("Skipped metadata")) }

@Test func volumePresenceDoesNotConfusePermissionWithOffline() { #expect(!VolumePresence.offline(path:"/Volumes/Archive/private",volume:"/Volumes/Archive",mounted:["/","/Volumes/Archive"])); #expect(VolumePresence.offline(path:"/Volumes/Archive/private",volume:"/Volumes/Archive",mounted:["/"])); #expect(!VolumePresence.offline(path:"/Volumes/Archive/private",volume:"/Volumes/Archive",mounted:nil)); #expect(!VolumePresence.offline(path:"/Volumes/Alias/private",volume:"/",mounted:["/"])); #expect(!VolumePresence.offline(path:"/Volumes/Renamed/private",volume:"/Volumes/OldName",mounted:["/"],stalePermission:true)) }
