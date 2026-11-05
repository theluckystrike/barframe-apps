import Foundation
import Testing
@testable import CronSpindleCore

func date(_ value:String)->Date {ISO8601DateFormatter().date(from:value)!}
func job(_ expression:String="* * * * *", minutes:Double=10,resource:String="Disk", zone:String="UTC")->Job {Job(name:"Job",expression:expression,zone:zone,minutes:minutes,resource:resource)}
@Test func requiresFiveFields() {#expect(throws:PlanError.self){try Cron("* * * *")}}
@Test func rejectsSeconds() {#expect(throws:PlanError.self){try Cron("0 * * * * *")}}
@Test func rejectsNames() {#expect(throws:PlanError.self){try Cron("0 1 * JAN *")}}
@Test func rejectsMacro() {#expect(throws:PlanError.self){try Cron("@hourly")}}
@Test func rejectsL() {#expect(throws:PlanError.self){try Cron("0 1 L * *")}}
@Test func rejectsW() {#expect(throws:PlanError.self){try Cron("0 1 2W * *")}}
@Test func rejectsHash() {#expect(throws:PlanError.self){try Cron("0 1 * * 1#2")}}
@Test func rejectsZeroStep() {#expect(throws:PlanError.self){try Cron("*/0 * * * *")}}
@Test func minuteBounds() {#expect(throws:PlanError.self){try Cron("60 * * * *")}}
@Test func reversedRange() {#expect(throws:PlanError.self){try Cron("5-2 * * * *")}}
@Test func emptyList() {#expect(throws:PlanError.self){try Cron("1,,2 * * * *")}}
@Test func numericStep() throws {#expect(try Cron("5/20 * * * *").fields[0] == [5,25,45])}
@Test func listsAndRanges() throws {#expect(try Cron("1,5-9/2 * * * *").fields[0] == [1,5,7,9])}
@Test func sundayAlias() throws {#expect(try Cron("0 1 * * 7").fields[4] == [0])}
@Test func dayOrSemantics() throws {let c=try Cron("0 1 12 * 3"); #expect(c.matches(DateComponents(month:10,day:14,hour:1,minute:0,weekday:4))); #expect(c.matches(DateComponents(month:10,day:12,hour:1,minute:0,weekday:2)))}
@Test func dayWildcardUsesWeekday() throws {let c=try Cron("0 1 * * 3"); #expect(!c.matches(DateComponents(month:10,day:12,hour:1,minute:0,weekday:2)))}
@Test func rejectsDurationZero() {#expect(throws:PlanError.self){try job(minutes:0).validate()}}
@Test func rejectsNegativeDuration() {#expect(throws:PlanError.self){try job(minutes:-1).validate()}}
@Test func rejectsNonfiniteDuration() {#expect(throws:PlanError.self){try job(minutes:.infinity).validate()}}
@Test func rejectsZone() {#expect(throws:PlanError.self){try job(zone:"Bogus/Zone").validate()}}
@Test func rejectsEmptyName() {var j=job();j.name=" ";#expect(throws:PlanError.self){try j.validate()}}
@Test func touchingDoesNotCollide() throws {let r=try Planner.analyze([job("0 2 * * *",minutes:30),job("30 2 * * *",minutes:30)],start:Fixtures.start,days:1);#expect(r.collisions.isEmpty)}
@Test func reportsExactOverlap() throws {let r=try Planner.analyze(Fixtures.jobs,start:Fixtures.start,days:1);#expect(r.collisions.count==1);#expect(r.collisions[0].end.timeIntervalSince(r.collisions[0].start)==1800)}
@Test func midnightLookback() throws {let r=try Planner.analyze([job("50 23 * * *",minutes:30),job("0 0 * * *",minutes:10)],start:Fixtures.start,days:1);#expect(r.collisions.first?.start==Fixtures.start)}
@Test func springSkipsWallTime() throws {let r=try Planner.analyze([job("30 2 * * *",zone:"America/New_York")],start:date("2026-03-08T05:00:00Z"),days:1);#expect(r.occurrences.isEmpty)}
@Test func autumnRepeatsWithOffsets() throws {let r=try Planner.analyze(Fixtures.dst,start:Fixtures.autumn,days:1);#expect(r.occurrences.count==2);#expect(r.occurrences[1].start.timeIntervalSince(r.occurrences[0].start)==3600);#expect(r.occurrences[0].wallLabel.contains("-04:00"));#expect(r.occurrences[1].wallLabel.contains("-05:00"))}
@Test func limitIsIncomplete() throws {let r=try Planner.analyze([job()],start:Fixtures.start,days:1,limit:2);#expect(r.incomplete);#expect(r.state=="Incomplete")}
@Test func horizonBound() {#expect(throws:PlanError.self){try Planner.analyze([],start:Fixtures.start,days:32)}}
@Test func blankResourceOptOut() throws {let r=try Planner.analyze([job("0 2 * * *",resource:""),job("0 2 * * *",resource:"")],start:Fixtures.start,days:1);#expect(r.collisions.isEmpty)}
@Test func resourceCaseNormalized() throws {let r=try Planner.analyze([job("0 2 * * *",resource:"disk"),job("0 2 * * *",resource:" Disk ")],start:Fixtures.start,days:1);#expect(r.collisions.count==1)}
@Test func proposalRemovesWithoutMutating() throws {let original=Fixtures.jobs;var revised=original;revised[1].expression="0 4 * * *";let a=try Planner.analyze(original,start:Fixtures.start,days:1);let b=try Planner.analyze(revised,start:Fixtures.start,days:1);#expect(Planner.difference(a.collisions,minus:b.collisions).count==1);#expect(original[1].expression=="30 2 * * *")}
@Test func intervalSubtraction() {let s=Fixtures.start;let a=Collision(pair:"pair",names:"a",resource:"disk",start:s,end:s.addingTimeInterval(100));let b=Collision(pair:"pair",names:"a",resource:"disk",start:s.addingTimeInterval(20),end:s.addingTimeInterval(60));let d=Planner.difference([a],minus:[b]);#expect(d.count==2);#expect(d[0].end==b.start);#expect(d[1].start==b.end)}
@Test func persistAndReopen() throws {let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:dir)};let f=dir.appendingPathComponent("plan.json");let p=Plan(jobs:Fixtures.jobs);try p.save(f);#expect(try Plan.load(f)==p)}
@Test func corruptStatePreserved() throws {let f=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:f)};let bytes=Data("broken".utf8);try bytes.write(to:f);#expect(throws:(any Error).self){try Plan.load(f)};#expect(try Data(contentsOf:f)==bytes)}
@Test func missingStateIsEmpty() throws {#expect(try Plan.load(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)).jobs.isEmpty)}
@Test func reportLabelsSample() throws {let r=try Planner.analyze(Fixtures.jobs,start:Fixtures.start,days:1);let s=Planner.report(r,jobs:Fixtures.jobs,sample:true);#expect(s.contains("Sample"));#expect(s.contains("UTC"));#expect(s.contains("60.0 minutes"))}
