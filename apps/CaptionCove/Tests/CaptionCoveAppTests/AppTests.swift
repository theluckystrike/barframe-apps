import AppKit
import Carbon
import SwiftUI
import Foundation
import Testing
import CaptionCoveCore
@testable import CaptionCove

@Suite(.serialized) @MainActor struct AppRegressionTests {
    func model() -> AppModel { _ = NSApplication.shared; return AppModel(folder:FileManager.default.temporaryDirectory.appendingPathComponent("CaptionCoveTests-"+UUID().uuidString)) }
    @Test func sampleRulesDoNotChangeLiveProjectOrPersistedEvidence() throws {
        let m=model(); defer { m.stop(); try? FileManager.default.removeItem(at:m.folder) }
        m.project=Project(rules:Rules(toleranceMS:250),result:Comparator.scan(reference:SRTParser.parse(Samples.reference),languages:[("Spanish",SRTParser.parse(Samples.reference))]))
        m.persist(); let before=try Data(contentsOf:m.stateURL)
        m.sampleMode=true; m.updateRules(Rules(toleranceMS:900,maxCPS:30,warnOverlap:false)); m.stop()
        #expect(m.rules.toleranceMS == 900)
        #expect(m.project.rules.toleranceMS == 250)
        #expect(m.project.result?.stale == false)
        #expect(try Data(contentsOf:m.stateURL) == before)
    }
    @Test func unrelatedValidationErrorDoesNotBlockCopyOrReadyState() {
        let m=model(); defer { try? FileManager.default.removeItem(at:m.folder) }
        m.project.result=Comparator.scan(reference:SRTParser.parse(Samples.reference),languages:[("Spanish",SRTParser.parse(Samples.reference))])
        m.error=true; m.message="Give this language a unique label"
        #expect(m.canCopy)
        #expect(m.state == .ready)
        m.project.result?.stale=true; #expect(!m.canCopy)
        m.project.result?.stale=false; m.checking=true; #expect(!m.canCopy)
    }
    @Test func spanishLiveLabelsAndInputErrorsAreLocalized() {
        let m=model(); let previous=m.language; defer { m.language=previous; try? FileManager.default.removeItem(at:m.folder) }
        m.language="es"; m.sampleMode=false
        #expect(m.label("Languages") == "Idiomas")
        #expect(m.reason(InputError.stale.localizedDescription) == "El permiso guardado del archivo está desactualizado")
        #expect(m.reason(InputError.unsupported.localizedDescription) == "Solo se admiten archivos SRT")
    }
    @Test func unreadableLanguageRetainsOtherLanguagesAndTheirFindings() {
        let reference=InputReference(label:"Reference",bookmark:Data(),filename:"reference.srt")
        let good=InputReference(label:"Good",bookmark:Data(),filename:"good.srt")
        let bad=InputReference(label:"Bad",bookmark:Data(),filename:"bad.srt")
        let work=AppModel.loadLiveProject(Project(reference:reference,languages:[good,bad])) { input in
            if input.label == "Bad" { throw InputError.unsupported }
            return (SRTParser.parse(input.label == "Good" ? Samples.spanish : Samples.reference),nil,Data([9]))
        }
        #expect(work.result?.rows.count == 3)
        #expect(work.result?.rows.first(where:{$0.label == "Good"})?.count(.missing) == 1)
        #expect(work.result?.rows.first(where:{$0.label == "Bad"})?.complete == false)
        #expect(work.result?.state == .incomplete)
        #expect(work.project.languages[0].bookmark == Data([9]))
    }
    @Test func resolvedStaleBookmarkIsRenewedInsteadOfRejected() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("moved.srt"); try Data(Samples.reference.utf8).write(to:url)
        let input=InputReference(label:"Reference",bookmark:Data([0]),filename:"old.srt")
        let read=try AppModel.readResolved(input,url:url,stale:true)
        #expect(read.0.complete)
        #expect(read.2 != input.bookmark)
        var stale=false
        #expect(try URL(resolvingBookmarkData:read.2,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale).resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
    }
    @Test func cleanSummaryIsDedicatedToCompletedDelivery() {
        let m=model(); defer { try? FileManager.default.removeItem(at:m.folder) }
        m.project.result=Comparator.scan(reference:SRTParser.parse(Samples.reference),languages:[("Spanish",SRTParser.parse(Samples.reference))])
        #expect(m.summaryText.contains("All language deliveries match"))
        #expect(!m.summaryText.contains("Choose a reference"))
    }
    @Test func startupPopoverIsPreparedWithoutAWindow() {
        let delegate=AppDelegate(); delegate.attach(delegate.ownedModel)
        #expect(delegate.popover.contentViewController != nil)
        #expect(delegate.hotkey != nil)
        #expect(delegate.detailWindow == nil)
    }
    @Test func newInstallDoesNotReserveFinderShortcut() {
        let previous=UserDefaults.standard.object(forKey:"hotkeyModifiers")
        defer { if let previous { UserDefaults.standard.set(previous,forKey:"hotkeyModifiers") } else { UserDefaults.standard.removeObject(forKey:"hotkeyModifiers") } }
        UserDefaults.standard.removeObject(forKey:"hotkeyModifiers")
        let m=model(); defer { try? FileManager.default.removeItem(at:m.folder) }
        #expect(m.hotkeyModifiers == "off")
        let hotkey=Hotkey(action:{})
        #expect(hotkey.register(key:m.hotkeyKey,modifiers:m.hotkeyModifiers) == noErr)
        #expect(hotkey.reference == nil)
    }
    @Test func savedProjectsAndLoginArgumentsSkipOnboarding() {
        #expect(AppDelegate.shouldShowOnboarding(project:Project(),arguments:[]))
        #expect(!AppDelegate.shouldShowOnboarding(project:Project(),arguments:["--login"]))
        #expect(!AppDelegate.shouldShowOnboarding(project:Project(languages:[InputReference(label:"Spanish",bookmark:Data(),filename:"a.srt")]),arguments:[]))
    }
    @Test func largeMatrixIsBoundedAtMinimumWindowSize() {
        #expect(ContentView.matrixHeight(rowCount:80) == 190)
        #expect(ContentView.matrixHeight(rowCount:5) <= 190)
        let m=model(); defer { try? FileManager.default.removeItem(at:m.folder) }
        m.sampleMode=false; m.selected="Language 1"
        m.project.reference=InputReference(label:"Reference",bookmark:Data(),filename:"reference.srt")
        m.project.languages=(1...80).map { InputReference(label:"Language \($0)",bookmark:Data(),filename:"language\($0).srt") }
        m.project.result=ScanResult(rows:(1...80).map { LanguageResult(label:"Language \($0)",findings:[],complete:true) })
        NSApp.appearance=NSAppearance(named:.darkAqua)
        let host=NSHostingView(rootView:ContentView(model:m).environment(\.colorScheme,.dark)); host.frame=NSRect(x:0,y:0,width:900,height:620)
        let window=NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=host; window.orderFront(nil); RunLoop.main.run(until:Date().addingTimeInterval(0.2)); window.display(); host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        #expect(host.fittingSize.height <= 620)
        #expect(ContentView.availableMatrixHeight(windowHeight:620,sample:false) <= 80)
        #expect(ContentView.availableMatrixHeight(windowHeight:760,sample:false) == 190)
    }
    @Test func localPolicyAndSupportRemainAvailableForProvisionalBrand() {
        #expect(ProductLinks.destination("https://{DOMAIN}/apps/captioncove/privacy/") == nil)
        #expect(ProductLinks.destination("https://barframe.com/apps/captioncove/privacy/") != nil)
        #expect(ProductLinks.localText("privacy").contains("CaptionCove"))
        #expect(ProductLinks.localText("support").contains("Choose again"))
    }
}
