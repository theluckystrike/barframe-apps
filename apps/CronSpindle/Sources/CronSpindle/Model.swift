import SwiftUI
import AppKit
import CronSpindleCore

@MainActor final class Model: ObservableObject {
    @Published var sample=false
    @Published var jobs: [Job]=[]
    @Published var selected: UUID?
    @Published var name=""
    @Published var expression="0 2 * * *"
    @Published var zone="UTC"
    @Published var duration="30"
    @Published var resource="Disk"
    @Published var start=Calendar.current.startOfDay(for:Date())
    @Published var days=7
    @Published var result: Analysis?
    @Published var proposed: Analysis?
    @Published var error: String?
    @Published var busy=false
    @Published var cancelled=false
    @Published var stale=true
    @Published var lastCheck: Date?
    @Published var pinned=UserDefaults.standard.object(forKey:"pinned") as? Bool ?? true { didSet {UserDefaults.standard.set(pinned,forKey:"pinned")} }
    @Published var displayZone=UserDefaults.standard.string(forKey:"displayZone") ?? "UTC" { didSet {UserDefaults.standard.set(displayZone,forKey:"displayZone")} }
    @Published var spanish=UserDefaults.standard.bool(forKey:"spanish") { didSet {UserDefaults.standard.set(spanish,forKey:"spanish")} }
    @Published var appearance=UserDefaults.standard.string(forKey:"appearance") ?? "System" { didSet {UserDefaults.standard.set(appearance,forKey:"appearance")} }
    private var task: Task<Void,Never>?
    private var generation=UUID()
    private var comparing=false
    private var live: [Job]=[]
    private let file: URL
    init(file: URL? = nil) {
        self.file=file ?? URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/CronSpindle/plan.json")
        if let saved=UserDefaults.standard.object(forKey:"previewStart") as? Date {start=saved}
        if let saved=UserDefaults.standard.object(forKey:"previewDays") as? Int, (1...31).contains(saved) {days=saved}
        do { live=try Plan.load(self.file).jobs; jobs=live }
        catch { self.error="Saved plan could not be read. It is preserved until you save or delete local data. \(error.localizedDescription)" }
    }
    func t(_ en: String, _ es: String) -> String { spanish ? es : en }
    var state: String { busy ? "Working" : cancelled ? "Cancelled" : jobs.isEmpty ? "No inputs" : stale && result != nil ? "Stale" : result?.state ?? "Not checked" }
    var status: String { (sample ? "S " : "") + (pinned ? state : "Not pinned") }
    var removed: [Collision] { guard let result,let proposed else{return []}; return Planner.difference(result.collisions,minus:proposed.collisions) }
    var added: [Collision] { guard let result,let proposed else{return []}; return Planner.difference(proposed.collisions,minus:result.collisions) }
    func toggleSample(_ value: Bool) {
        cancel(); sample=value; jobs=value ? Fixtures.jobs : live; start=value ? Fixtures.start : (UserDefaults.standard.object(forKey:"previewStart") as? Date ?? Calendar.current.startOfDay(for:Date())); days=value ? 7 : max(1,min(31,UserDefaults.standard.object(forKey:"previewDays") as? Int ?? 7)); result=nil; proposed=nil; error=nil; selected=nil; stale=true; cancelled=false
        if value { select(jobs[1]); analyze() } else {newJob()}
    }
    func savePreviewSettings() {
        guard !sample else {return}
        UserDefaults.standard.set(start,forKey:"previewStart");UserDefaults.standard.set(days,forKey:"previewDays")
    }
    func resetSample() { toggleSample(true) }
    func dstSample() { toggleSample(true); cancel(); jobs=Fixtures.dst; start=Fixtures.autumn; days=1; select(jobs[0]); analyze() }
    func select(_ job: Job) { selected=job.id; name=job.name; expression=job.expression; zone=job.zone; duration=String(job.minutes); resource=job.resource; proposed=nil }
    func newJob() { selected=nil; name=""; expression="0 2 * * *"; zone="UTC"; duration="30"; resource="Disk"; proposed=nil }
    func draft() throws -> Job {
        guard let minutes=Double(duration) else { throw PlanError("Enter a positive duration in minutes") }
        let job=Job(id:selected ?? UUID(),name:name,expression:expression,zone:zone,minutes:minutes,resource:resource)
        try job.validate(); return job
    }
    func save() {
        do {
            let job=try draft(); var next=jobs
            if let index=next.firstIndex(where:{$0.id==job.id}) { next[index]=job } else { guard next.count<50 else { throw PlanError("Plan is limited to 50 jobs") }; next.append(job) }
            if !sample { try Plan(jobs:next).save(file); live=next }
            jobs=next; selected=job.id; error=nil; analyze()
        } catch { self.error=error.localizedDescription }
    }
    func deleteJob() {
        guard let selected else { return }
        let next=jobs.filter{$0.id != selected}
        do { if !sample { try Plan(jobs:next).save(file); live=next }; jobs=next; newJob(); analyze() } catch { self.error=error.localizedDescription }
    }
    func clear() {
        cancel()
        do { if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }; live=[]; if !sample {jobs=[]}; result=nil; proposed=nil; error=nil; stale=true; newJob() } catch { self.error=error.localizedDescription }
    }
    func cancel() { if busy {cancelled=true}; task?.cancel(); generation=UUID(); busy=false; stale=true }
    func invalidate() { cancel(); proposed=nil }
    func draftChanged() { proposed=nil; if busy && comparing {cancel()} }
    func analyze(compare: Bool=false) {
        cancel(); let token=UUID(); generation=token
        guard !jobs.isEmpty else {result=nil;proposed=nil;cancelled=false;return}
        var candidate=jobs
        if compare {
            do {
                guard let selected, let index=candidate.firstIndex(where:{$0.id==selected}) else { throw PlanError("Save a job before comparing a proposal") }
                let edited=try draft()
                guard edited.name==candidate[index].name,edited.zone==candidate[index].zone,edited.resource==candidate[index].resource else { throw PlanError("Compare changes to expression and duration only. Save other job edits first.") }
                candidate[index]=edited
            } catch { self.error=error.localizedDescription; return }
        }
        let original=jobs, start=start, days=days
        comparing=compare; busy=true; cancelled=false; error=nil
        task=Task {
            let worker=Task.detached(priority:.userInitiated) { () throws -> (Analysis,Analysis?) in
                let baseline=try Planner.analyze(original,start:start,days:days)
                return (baseline,compare ? try Planner.analyze(candidate,start:start,days:days) : nil)
            }
            do {
                let values=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                guard generation==token else{return}
                result=values.0; proposed=values.1; busy=false; stale=false; lastCheck=Date()
            } catch { guard generation==token else{return}; self.error=error.localizedDescription; busy=false; stale=true }
        }
    }
    func copyReport() {
        guard let result else {return}
        var text=Planner.report(result,jobs:jobs,sample:sample)
        if stale {text="STALE inputs changed or analysis cancelled\n"+text}
        if let proposed {
            text+="\nProposal for \(name) using \(expression) duration \(duration) minutes\nProposal state \(proposed.state)\nAdded windows \(added.count) Removed windows \(removed.count)"
            for (label,windows) in [("Added",added),("Removed",removed)] { for w in windows { text+="\n\(label) \(w.names) \(Planner.label(w.start)) to \(Planner.label(w.end))" } }
        }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
    }
}
