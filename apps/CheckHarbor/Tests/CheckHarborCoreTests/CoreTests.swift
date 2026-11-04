import Foundation
import Testing
@testable import CheckHarborCore
func inbox(_ runs:[Run]) -> Inbox { var i=Inbox(); i.ingest(repository:"harbor/demo",runs:runs); return i }
@Test func failureCreatesEpisode() { #expect(inbox([Run(id:1)]).active.count == 1) }
@Test func repeatedFailureDeduplicates() { let i=inbox([Run(id:1),Run(id:2)]); #expect(i.active.count == 1); #expect(i.active[0].failures == 2) }
@Test func matchingRecoveryCloses() { #expect(inbox([Run(id:1),Run(id:2,conclusion:"success")]).recovered.count == 1) }
@Test func unrelatedBranchDoesNotClose() { #expect(inbox([Run(id:1),Run(id:2,branch:"docs",conclusion:"success")]).active.count == 1) }
@Test func unrelatedWorkflowDoesNotClose() { #expect(inbox([Run(id:1),Run(id:2,workflow:11,conclusion:"success")]).active.count == 1) }
@Test func unrelatedRepositoryDoesNotClose() { var i=inbox([Run(id:1)]); i.ingest(repository:"other/demo",runs:[Run(id:2,conclusion:"success")]); #expect(i.active.count == 1) }
@Test func cancelledDoesNotRecover() { #expect(inbox([Run(id:1),Run(id:2,conclusion:"cancelled")]).active.count == 1) }
@Test func skippedDoesNotRecover() { #expect(inbox([Run(id:1),Run(id:2,conclusion:"skipped")]).active.count == 1) }
@Test func queuedDoesNotRecover() { #expect(inbox([Run(id:1),Run(id:2,status:"queued",conclusion:"success")]).active.count == 1) }
@Test func sortedInputMatchesRecovery() { #expect(inbox([Run(id:3,conclusion:"success"),Run(id:1),Run(id:2)]).recovered[0].failures == 2) }
@Test func oldFailureCannotReopen() { var i=inbox([Run(id:5,conclusion:"success")]); i.ingest(repository:"harbor/demo",runs:[Run(id:1)]); #expect(i.active.isEmpty) }
@Test func repeatedPollDoesNotDuplicate() { var i=inbox(Fixtures.initial); i.ingest(repository:"harbor/demo",runs:Fixtures.initial); #expect(i.active[0].failures == 2) }
@Test func laterFailureStartsNewEpisode() { #expect(inbox([Run(id:1),Run(id:2,conclusion:"success"),Run(id:3)]).episodes.count == 2) }
@Test func rerunRecoveryWorks() { #expect(inbox([Run(id:1,number:1),Run(id:1,conclusion:"success",number:1,attempt:2)]).recovered.count == 1) }
@Test func acknowledgementPersists() throws { var i=inbox([Run(id:1)]); i.acknowledge(i.active[0].id); let decoded=try JSONDecoder().decode(Inbox.self,from:JSONEncoder().encode(i)); #expect(decoded.active[0].acknowledged) }
@Test func snoozePreservesUnresolved() { var i=inbox([Run(id:1)]); i.snooze(i.active[0].id,until:Date().addingTimeInterval(60)); #expect(i.active[0].snoozed(at:Date())); #expect(i.active.count == 1) }
@Test func expiredSnoozeBecomesVisible() { var i=inbox([Run(id:1)]); i.snooze(i.active[0].id,until:.distantPast); #expect(!i.active[0].snoozed(at:Date())) }
@Test func emptyFetchPreservesHistory() { var i=inbox([Run(id:1)]); let before=i; i.ingest(repository:"harbor/demo",runs:[]); #expect(i == before) }
@Test func retentionPreservesActive() { var i=inbox(Fixtures.recovery); i.prune(before:.distantFuture); #expect(i.recovered.isEmpty); #expect(i.active.count == 1) }
@Test func branchlessRunIgnored() { var r=Run(id:1); r.head_branch=nil; #expect(inbox([r]).episodes.isEmpty) }
@Test func repositoryValidation() { #expect(Validation.repository(" Owner/Repo ") == "owner/repo"); #expect(Validation.repository("https://github.com/o/r") == nil) }
@Test func traversalRejected() { #expect(Validation.repository("owner/..") == nil); #expect(Validation.repository("../repo") == nil) }
@Test func validLinkAccepted() { #expect(Validation.runURL("https://github.com/harbor/demo/actions/runs/123",repository:"harbor/demo") != nil) }
@Test func spoofedLinkRejected() { #expect(Validation.runURL("https://github.com.evil.test/harbor/demo/actions/runs/1",repository:"harbor/demo") == nil); #expect(Validation.runURL("https://github.com@evil.test/harbor/demo/actions/runs/1",repository:"harbor/demo") == nil) }
@Test func wrongRepositoryLinkRejected() { #expect(Validation.runURL("https://github.com/other/demo/actions/runs/1",repository:"harbor/demo") == nil) }
@Test func rateLimitUsesReset() { let now=Date(timeIntervalSince1970:100); #expect(Validation.backoff(status:403,headers:["X-RateLimit-Remaining":"0","X-RateLimit-Reset":"500"],now:now) == Date(timeIntervalSince1970:500)) }
@Test func retryAfterHonored() { let now=Date(timeIntervalSince1970:100); #expect(Validation.backoff(status:429,headers:["Retry-After":"120"],now:now) == Date(timeIntervalSince1970:220)) }
@Test func forbiddenBacksOff() { let now=Date(); #expect(Validation.backoff(status:403,headers:[:],now:now)! > now) }
@Test func sampleCannotFetch() { #expect(!Validation.mayFetch(sample:true,until:nil,now:Date())) }
@Test func backoffBlocksFetch() { #expect(!Validation.mayFetch(sample:false,until:.distantFuture,now:Date())) }
@Test func liveCanFetch() { #expect(Validation.mayFetch(sample:false,until:.distantPast,now:Date())) }
@Test func timeoutCountsAsFailure() { #expect(inbox([Run(id:1,conclusion:"timed_out")]).active.count == 1) }
@Test func neutralIsNotRecovery() { #expect(inbox([Run(id:1),Run(id:2,conclusion:"neutral")]).active.count == 1) }

@Test func cancelledRunCannotHideOutOfOrderRecovery() {
    var i=inbox([Run(id:1),Run(id:2,status:"in_progress",conclusion:nil),Run(id:3,conclusion:"cancelled")])
    i.ingest(repository:"harbor/demo",runs:[Run(id:2,conclusion:"success")])
    #expect(i.active.isEmpty); #expect(i.recovered.first?.recovery?.id == 2)
}
@Test func cancelledRunCannotHideLateFailure() {
    var i=inbox([Run(id:1),Run(id:3,conclusion:"cancelled")])
    i.ingest(repository:"harbor/demo",runs:[Run(id:2)])
    #expect(i.active.first?.failures == 2); #expect(i.active.first?.latest.id == 2)
    i.ingest(repository:"harbor/demo",runs:[Run(id:2)])
    #expect(i.active.first?.failures == 2)
}
@Test func lateOlderSuccessCannotCloseNewerFailure() {
    var i=inbox([Run(id:1),Run(id:3)])
    i.ingest(repository:"harbor/demo",runs:[Run(id:2,conclusion:"success")])
    #expect(i.active.first?.latest.id == 3)
    i.ingest(repository:"harbor/demo",runs:[Run(id:4,conclusion:"success")])
    #expect(i.active.isEmpty)
}
@Test func lateFailurePreservesNewestFailureLink() {
    var i=inbox([Run(id:3)])
    i.ingest(repository:"harbor/demo",runs:[Run(id:1),Run(id:2)])
    #expect(i.active.first?.first.id == 1); #expect(i.active.first?.latest.id == 3)
    #expect(i.active.first?.failures == 3)
}
@Test func processedAttemptsSurviveReloadAndRetention() throws {
    var i=inbox(Fixtures.recovery)
    i.prune(before:.distantFuture)
    i=try JSONDecoder().decode(Inbox.self,from:JSONEncoder().encode(i))
    i.ingest(repository:"harbor/demo",runs:Fixtures.recovery)
    #expect(i.active.count == 1); #expect(i.recovered.isEmpty)
    #expect(i.active.first?.failures == 1)
}
@Test func legacyCancelledCursorDoesNotHideRecovery() throws {
    let original=inbox([Run(id:1)])
    var payload=try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
    payload.removeValue(forKey:"processed")
    payload["cursors"]=["harbor/demo|10|main":["number":3,"attempt":1]]
    var i=try JSONDecoder().decode(Inbox.self,from:JSONSerialization.data(withJSONObject:payload))
    i.ingest(repository:"harbor/demo",runs:[Run(id:2,conclusion:"success")])
    #expect(i.active.isEmpty)
}
