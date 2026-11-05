import Foundation

public struct Cue: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let start: Int
    public let end: Int
    public let text: String
    public init(id: Int, start: Int, end: Int, text: String) { self.id=id; self.start=start; self.end=end; self.text=text }
    public var visibleText: String {
        text.replacingOccurrences(of: #"</?(?:b|i|u|font)(?:\s+[^>]*)?>"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
    /// Swift extended grapheme clusters. Whitespace counts except line separators.
    public var visibleCharacters: Int { visibleText.filter { $0 != "\n" && $0 != "\r" }.count }
    public var cps: Double? { end > start ? Double(visibleCharacters) * 1000 / Double(end-start) : nil }
}
public struct ParsedSRT: Codable, Equatable, Sendable {
    public var cues: [Cue]
    public var errors: [String]
    public var complete: Bool { errors.isEmpty && !cues.isEmpty }
    public init(cues: [Cue], errors: [String] = []) { self.cues=cues; self.errors=errors }
}
public enum SRTParser {
    public static func timestamp(_ input: String) -> Int? {
        let normalized=input.trimmingCharacters(in:.whitespaces).replacingOccurrences(of:".",with:",")
        let parts=normalized.split(separator:":",omittingEmptySubsequences:false)
        guard parts.count == 3, !parts[0].isEmpty, parts[1].count == 2 else { return nil }
        let tail=parts[2].split(separator:",",omittingEmptySubsequences:false)
        guard tail.count == 2, tail[0].count == 2, tail[1].count == 3,
              [parts[0],parts[1],tail[0],tail[1]].allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let h=Int(parts[0]), let m=Int(parts[1]), let s=Int(tail[0]), let ms=Int(tail[1]),
              h < 100_000, (0..<60).contains(m), (0..<60).contains(s) else { return nil }
        return ((h*60+m)*60+s)*1000+ms
    }
    public static func parse(data: Data) -> ParsedSRT {
        guard let text=String(data:data, encoding:.utf8) else { return ParsedSRT(cues:[],errors:["File is not valid UTF8"] ) }
        return parse(text)
    }
    public static func parse(_ source: String) -> ParsedSRT {
        let text=source.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
        let lines=text.components(separatedBy:"\n")
        var blocks=[[String]](), current=[String]()
        for line in lines {
            if line.trimmingCharacters(in:.whitespaces).isEmpty {
                if !current.isEmpty { blocks.append(current); current=[] }
            } else { current.append(line) }
        }
        if !current.isEmpty { blocks.append(current) }
        var cues=[Cue](), errors=[String](), ids=Set<Int>()
        for (index, block) in blocks.enumerated() {
            guard block.count >= 2, let id=Int(block[0].trimmingCharacters(in:.whitespaces)), id>0 else {
                errors.append("Block \(index+1) has an invalid cue ID or missing timing"); continue
            }
            if !ids.insert(id).inserted { errors.append("Duplicate cue ID \(id)"); continue }
            let times=block[1].trimmingCharacters(in:.whitespaces).components(separatedBy:"-->").map { $0.trimmingCharacters(in:.whitespaces) }
            // Position coordinates follow the end timestamp and are not cue timing.
            let endToken=times.last?.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            guard times.count == 2, let start=timestamp(times[0]), let end=timestamp(endToken) else {
                errors.append("Cue \(id) has a malformed timecode"); continue
            }
            let cue=Cue(id:id,start:start,end:end,text:block.dropFirst(2).joined(separator:"\n"))
            if end <= start { errors.append("Cue \(id) has zero or reversed duration") }
            cues.append(cue)
        }
        if blocks.isEmpty { errors.append("No subtitle cues found") }
        return ParsedSRT(cues:cues,errors:errors)
    }
}
public struct Rules: Codable, Equatable, Sendable {
    public var toleranceMS: Int
    public var maxCPS: Double
    public var warnOverlap: Bool
    public init(toleranceMS: Int=100, maxCPS: Double=20, warnOverlap: Bool=true) {
        self.toleranceMS=max(0,toleranceMS); self.maxCPS=max(1,maxCPS); self.warnOverlap=warnOverlap
    }
    public var valid: Bool { toleranceMS >= 0 && maxCPS >= 1 && maxCPS.isFinite }
}
public enum IssueKind: String, Codable, CaseIterable, Sendable {
    case missing="Missing", extra="Extra", drift="Timing", text="Text", overlap="Overlap", invalid="Invalid", identity="IDs unsuitable"
    public var parityFailure: Bool { self == .missing || self == .extra || self == .drift || self == .identity || self == .invalid }
}
public struct Finding: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(kind.rawValue)|\(cueID ?? 0)|\(reason)" }
    public let kind: IssueKind
    public let cueID: Int?
    public let start: Int?
    public let end: Int?
    public let startDrift: Int?
    public let endDrift: Int?
    public let reason: String
    public init(kind: IssueKind, cueID: Int? = nil, start: Int? = nil, end: Int? = nil, startDrift: Int? = nil, endDrift: Int? = nil, reason: String) {
        self.kind=kind; self.cueID=cueID; self.start=start; self.end=end; self.startDrift=startDrift; self.endDrift=endDrift; self.reason=reason
    }
}
public struct LanguageResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public var findings: [Finding]
    public var complete: Bool
    public init(label: String, findings: [Finding], complete: Bool) { self.label=label; self.findings=findings; self.complete=complete }
    public func count(_ kind: IssueKind) -> Int { findings.filter { $0.kind == kind }.count }
}
public enum ReviewState: String, Codable, Sendable { case ready="Ready", issues="Issues", incomplete="Incomplete" }
public struct ScanResult: Codable, Equatable, Sendable {
    public var rows: [LanguageResult]
    public var date: Date
    public var sample: Bool
    public var rules: Rules
    public var stale: Bool
    public var state: ReviewState {
        if stale || rows.isEmpty || rows.contains(where: { !$0.complete }) { return .incomplete }
        return rows.contains(where: { $0.findings.contains(where: { $0.kind.parityFailure }) }) ? .issues : .ready
    }
    public var warningCount:Int { rows.reduce(0) { $0 + $1.findings.filter { !$0.kind.parityFailure }.count } }
    public init(rows:[LanguageResult], date:Date=Date(), sample:Bool=false, rules:Rules=Rules(), stale:Bool=false) { self.rows=rows; self.date=date; self.sample=sample; self.rules=rules; self.stale=stale }
    public func report(dialogue: [String:ParsedSRT]? = nil) -> String {
        var lines=["CaptionCove \(sample ? "Sample " : "")delivery report", "State \(state.rawValue)", "Local warnings \(warningCount)", "Checked \(ISO8601DateFormatter().string(from:date))", "Tolerance \(rules.toleranceMS) ms", "Text rule \(rules.maxCPS) characters per second", "Counts use visible grapheme clusters including spaces and excluding line breaks", "Overlaps are warnings and do not imply parity failure"]
        if stale { lines.append("Stale results require a new check") }
        for row in rows {
            lines.append("Language \(row.label) \(row.complete ? "complete" : "incomplete")")
            if row.findings.isEmpty { lines.append("No findings") }
            for f in row.findings {
                lines.append("\(f.kind.rawValue) cue \(f.cueID.map(String.init) ?? "unknown") timing \(f.start.map(formatTime) ?? "unknown") to \(f.end.map(formatTime) ?? "unknown") \(f.reason)")
                if let id=f.cueID, let cue=dialogue?[row.label]?.cues.first(where:{$0.id == id}) { lines.append("Dialogue \(cue.text)") }
            }
        }
        return lines.joined(separator:"\n")
    }
}
public func formatTime(_ value:Int) -> String { String(format:"%02d:%02d:%02d,%03d",value/3600000,(value/60000)%60,(value/1000)%60,value%1000) }
public enum Comparator {
    // A design limit protects the native review UI from pathological overlap sets.
    public static let findingLimit=5000
    static func truncated(_ findings:[Finding])->[Finding] {
        Array(findings.prefix(findingLimit))+[Finding(kind:.invalid,reason:"Too many findings. The result is truncated and incomplete")]
    }
    public static func local(_ parsed:ParsedSRT, rules:Rules) -> [Finding] {
        var result=parsed.errors.prefix(findingLimit).map { Finding(kind:.invalid, reason:$0) }
        if result.count >= findingLimit { return truncated(result) }
        for c in parsed.cues {
            if result.count >= findingLimit { return truncated(result) }
            if c.visibleText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { result.append(Finding(kind:.text,cueID:c.id,start:c.start,end:c.end,reason:"Empty visible text")) }
            if let speed=c.cps, speed>rules.maxCPS { result.append(Finding(kind:.text,cueID:c.id,start:c.start,end:c.end,reason:String(format:"%.1f characters per second exceeds user rule %.1f",speed,rules.maxCPS))) }
        }
        if rules.warnOverlap {
            let sorted=parsed.cues.filter{$0.end > $0.start}.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
            var active=[Cue]()
            for c in sorted {
                active.removeAll { $0.end <= c.start }
                for other in active {
                    if result.count >= findingLimit { return truncated(result) }
                    result.append(Finding(kind:.overlap,cueID:c.id,start:c.start,end:c.end,reason:"Overlaps cue \(other.id) by \(min(other.end,c.end)-c.start) ms")) }
                active.append(c)
            }
        }
        return result
    }
    public static func scan(reference:ParsedSRT, languages:[(String,ParsedSRT)], rules:Rules=Rules(), sample:Bool=false) -> ScanResult {
        let referenceFindings=local(reference,rules:rules)
        let referenceComplete=reference.complete && rules.valid && !referenceFindings.contains(where:{$0.kind == .invalid})
        var rows=[LanguageResult(label:"Reference",findings:referenceFindings,complete:referenceComplete)]
        let ref=Dictionary(reference.cues.map{($0.id,$0)},uniquingKeysWith: { a,_ in a })
        let referenceByTime=reference.cues.sorted { $0.start < $1.start }
        for (label,parsed) in languages {
            var findings=local(parsed,rules:rules)
            var complete=referenceComplete && parsed.complete && rules.valid && !findings.contains(where:{$0.kind == .invalid})
            let input=Dictionary(parsed.cues.map{($0.id,$0)},uniquingKeysWith: { a,_ in a })
            let missing=Set(ref.keys).subtracting(input.keys), extra=Set(input.keys).subtracting(ref.keys)
            let shared=Set(ref.keys).intersection(input.keys)
            // Identity changes make a complete cue parity claim unsafe. Never align by position.
            let shiftedIDs=shared.filter { id in
                guard let a=ref[id], let b=input[id] else { return false }
                guard abs(b.start-a.start)>rules.toleranceMS || abs(b.end-a.end)>rules.toleranceMS else { return false }
                var low=0, high=referenceByTime.count
                while low<high {
                    let middle=(low+high)/2
                    if referenceByTime[middle].start < b.start-rules.toleranceMS { low=middle+1 } else { high=middle }
                }
                while low<referenceByTime.count && referenceByTime[low].start<=b.start+rules.toleranceMS {
                    let candidate=referenceByTime[low]
                    if candidate.id != id && abs(b.end-candidate.end)<=rules.toleranceMS { return true }
                    low+=1
                }
                return false
            }.sorted()
            let consecutiveShift=zip(shiftedIDs,shiftedIDs.dropFirst()).contains { $1 == $0+1 }
            let unsuitable = (!missing.isEmpty && !extra.isEmpty) || (!missing.isEmpty && (consecutiveShift || (!shared.isEmpty && shiftedIDs.count*2>shared.count)))
            if unsuitable {
                findings.append(Finding(kind:.identity,reason:"Cue IDs differ and may be renumbered. ID matching is unsuitable. Supply the original cue map")); complete=false
            }
            for id in missing.sorted() { findings.append(Finding(kind:.missing,cueID:id,start:ref[id]?.start,end:ref[id]?.end,reason:"Reference cue is absent")) }
            for id in extra.sorted() { findings.append(Finding(kind:.extra,cueID:id,start:input[id]?.start,end:input[id]?.end,reason:"Cue is absent from reference")) }
            // Do not mislabel shared IDs as timing drift when their identity is ambiguous.
            for id in shared.sorted() where !unsuitable {
                guard let a=ref[id], let b=input[id] else { continue }
                let start=b.start-a.start, end=b.end-a.end
                if abs(start)>rules.toleranceMS || abs(end)>rules.toleranceMS {
                    findings.append(Finding(kind:.drift,cueID:id,start:b.start,end:b.end,startDrift:start,endDrift:end,reason:"Signed start drift \(signed(start)) ms and end drift \(signed(end)) ms"))
                }
            }
            if findings.count > findingLimit { findings=truncated(findings); complete=false }
            rows.append(LanguageResult(label:label,findings:findings,complete:complete))
        }
        if languages.isEmpty { rows.append(LanguageResult(label:"Languages",findings:[Finding(kind:.invalid,reason:"Choose at least one language SRT")],complete:false)) }
        return ScanResult(rows:rows,sample:sample,rules:rules)
    }
    static func signed(_ value:Int) -> String { value >= 0 ? "+\(value)" : "\(value)" }
}
public enum Samples {
    public static let reference="1\n00:00:01,000 --> 00:00:03,000\nA quiet opening\n\n2\n00:00:04,000 --> 00:00:06,000\nThe middle scene\n\n3\n00:00:07,000 --> 00:00:09,000\nA gentle ending\n"
    public static let spanish="1\n00:00:01,000 --> 00:00:03,000\nInicio tranquilo\n\n3\n00:00:07,000 --> 00:00:09,000\nUn final suave\n"
    public static let french="1\n00:00:01,000 --> 00:00:03,000\nUne ouverture calme\n\n2\n00:00:04,000 --> 00:00:06,000\nLa scène du milieu\n\n3\n00:00:07,450 --> 00:00:09,450\nUne fin douce\n"
    public static let overlap="1\n00:00:01,000 --> 00:00:05,000\n<i></i>\n\n2\n00:00:04,000 --> 00:00:06,000\nAn intentional overlap\n\n3\n00:00:07,000 --> 00:00:09,000\nClosing\n"
    public static var languages:[(String,String)] { [("Spanish",spanish),("French",french),("Empty translation",""),("Overlap example",overlap)] }
}
public struct InputReference: Codable, Equatable, Identifiable {
    public let id: UUID
    public var label: String
    public var bookmark: Data
    public var filename: String
    public var modification: Date?
    public init(id:UUID=UUID(), label:String, bookmark:Data, filename:String, modification:Date?=nil) { self.id=id; self.label=label; self.bookmark=bookmark; self.filename=filename; self.modification=modification }
}
public struct Project: Codable, Equatable {
    public var reference:InputReference?
    public var languages:[InputReference]
    public var rules:Rules
    public var result:ScanResult?
    public init(reference:InputReference?=nil,languages:[InputReference]=[],rules:Rules=Rules(),result:ScanResult?=nil) { self.reference=reference; self.languages=languages; self.rules=rules; self.result=result }
}
public enum Persistence {
    public static func save(_ project:Project,to url:URL) throws { try JSONEncoder().encode(project).write(to:url,options:.atomic) }
    public static func load(from url:URL) throws -> Project {
        let project=try JSONDecoder().decode(Project.self,from:Data(contentsOf:url))
        guard project.rules.valid, project.result?.sample != true, Set(project.languages.map(\.label)).count == project.languages.count, !project.languages.contains(where: { $0.label == "Reference" || $0.label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }) else { throw CocoaError(.fileReadCorruptFile) }
        return project
    }
}
