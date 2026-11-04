import Foundation
import Testing
import RouteLoomCore

struct CoreTests {
    let t = Fixtures.base
    func o(_ error: Transport? = nil, _ status: Int? = nil) -> Observation { Fixtures.observation(t,error,status:status) }
    @Test func acceptsHTTPS() throws { #expect(try Endpoint.validate("https://health.example/check?a=b").host == "health.example") }
    @Test func trimsOuterWhitespace() throws { #expect(try Endpoint.validate("  https://health.example \n").scheme == "https") }
    @Test func rejectsHTTP() { #expect(throws:URLRuleError.https) { try Endpoint.validate("http://health.example") } }
    @Test func rejectsMissingHost() { #expect(throws:(any Error).self) { try Endpoint.validate("https://") } }
    @Test func rejectsPassword() { #expect(throws:URLRuleError.credentials) { try Endpoint.validate("https://alice:secret@health.example") } }
    @Test func rejectsUsernameOnly() { #expect(throws:URLRuleError.credentials) { try Endpoint.validate("https://alice@health.example") } }
    @Test func rejectsFragment() { #expect(throws:URLRuleError.host) { try Endpoint.validate("https://health.example/#secret") } }
    @Test func rejectsWhitespace() { #expect((try? Endpoint.validate("https://health.example/a b")) == nil) }
    @Test func healthyPair() { #expect(PairState.classify(o(),o()) == .healthy) }
    @Test func workOnlyTimeout() { #expect(PairState.classify(o(),o(.timeout)) == .targetOnly) }
    @Test func referenceOnlyOffline() { #expect(PairState.classify(o(.offline),o()) == .referenceOnly) }
    @Test func sharedTLS() { #expect(PairState.classify(o(.tls),o(.tls)) == .shared) }
    @Test func missingObservationInsufficient() { #expect(PairState.classify(nil,o()) == .insufficient) }
    @Test func cancelledInsufficient() { #expect(PairState.classify(o(.cancelled),o()) == .insufficient) }
    @Test func unknownInsufficient() { #expect(PairState.classify(o(.unknown),o(.timeout)) == .insufficient) }
    @Test func httpErrorProvesResponseButUnhealthy() { let a = o(nil,503);#expect(a.known && !a.healthy);#expect(a.summary.contains("response received"));#expect(PairState.classify(o(),a) == .targetOnly) }
    @Test func redirectsUnhealthyWithoutFollowing() { #expect(!o(nil,302).healthy) }
    @Test func timeoutClassification() { #expect(Transport.classify(URLError(.timedOut)) == .timeout) }
    @Test func offlineClassification() { #expect(Transport.classify(URLError(.notConnectedToInternet)) == .offline) }
    @Test func certificateClassification() { #expect(Transport.classify(URLError(.serverCertificateUntrusted)) == .tls) }
    @Test func dnsClassification() { #expect(Transport.classify(URLError(.cannotFindHost)) == .dns) }
    @Test func connectionClassification() { #expect(Transport.classify(URLError(.networkConnectionLost)) == .connection) }
    @Test func cancellationClassification() { #expect(Transport.classify(URLError(.cancelled)) == .cancelled) }
    @Test func nonURLErrorUnknown() { #expect(Transport.classify(NSError(domain:"other",code:123)) == .unknown) }
    @Test func healthyTransitionOpensAndRecoveryCloses() {
        var s = Session(name:"Pair",referenceHost:"r.example",workHost:"w.example",started:t,sample:false)
        s.append(PairCheck(at:t,reference:o(),work:o()))
        s.append(PairCheck(at:t.addingTimeInterval(30),reference:o(),work:o(.timeout)))
        #expect(s.incidents.count == 1 && s.incidents[0].end == nil)
        s.append(PairCheck(at:t.addingTimeInterval(60),reference:o(),work:o()))
        #expect(s.incidents[0].end == t.addingTimeInterval(60))
        #expect(s.incidents[0].observedDuration == 30)
    }
    @Test func unhealthyFirstCheckHasNoHealthyBaseline() {
        var s = Session(name:"Pair",referenceHost:"r",workHost:"w",started:t,sample:false)
        s.append(PairCheck(at:t,reference:o(.offline),work:o(.offline)))
        #expect(s.incidents.isEmpty && s.current == .shared)
    }
    @Test func unknownObservationDoesNotCloseIncident() {
        var s = Session(name:"Pair",referenceHost:"r",workHost:"w",started:t,sample:false)
        s.append(PairCheck(at:t,reference:o(),work:o()))
        s.append(PairCheck(at:t.addingTimeInterval(30),reference:o(),work:o(.timeout)))
        s.append(PairCheck(at:t.addingTimeInterval(60),reference:nil,work:nil))
        #expect(s.incidents[0].end == nil && s.incidents[0].observedDuration == 0)
    }
    @Test func sleepGapExcludedFromObservedSpan() {
        let s = Fixtures.session()
        #expect(s.gaps[0].duration == 300)
        #expect(s.incidents[1].observedDuration == 30)
        #expect(s.incidents[0].observedDuration == 60)
    }
    @Test func backwardsGapClamped() { #expect(Gap(start:t,end:t.addingTimeInterval(-20),reason:"Clock").duration == 0) }
    @Test func stoppedSessionRejectsChecks() { var s = Fixtures.session();let count = s.checks.count;s.append(PairCheck(at:t,reference:o(),work:o()));#expect(s.checks.count == count) }
    @Test func outOfOrderCheckRejected() {
        var s = Session(name:"Pair",referenceHost:"r",workHost:"w",started:t,sample:false)
        s.append(PairCheck(at:t,reference:o(),work:o()));s.append(PairCheck(at:t.addingTimeInterval(-1),reference:o(),work:o(.timeout)));#expect(s.checks.count == 1)
    }
    @Test func reportRedactsEndpointPathAndQuery() throws {
        let r = try Endpoint.validate("https://reference.example/private/customer?token=SECRET")
        let w = try Endpoint.validate("https://work.example/sensitive?access=SECRET")
        let s = Session(name:"Secret private title",referenceHost:Endpoint.host(r),workHost:Endpoint.host(w),started:t,sample:false)
        let report = Report.text(s)
        #expect(report.contains("work.example") && !report.contains("SECRET") && !report.contains("/private") && !report.contains("sensitive") && !report.contains("Secret private title"))
    }
    @Test func reportContainsObservationsAndGaps() { let report = Report.text(Fixtures.session());#expect(report.contains("Sample") && report.contains("Unknown gap") && report.contains("response received") && report.contains("timeout")) }
    @Test func comparisonCountsAreAccurate() { let s = Fixtures.session();#expect(s.counts[.targetOnly] == 2);#expect(s.counts[.shared] == 2);#expect(Report.comparison(s,Fixtures.earlier).contains("Work only failure · recent 2 · earlier 0")) }
    @Test func differentHostsWarn() { var earlier = Fixtures.earlier;earlier.workHost = "other.example";#expect(Report.comparison(Fixtures.session(),earlier).contains("compare with care")) }
    @Test func allSampleScenariosHaveRecoveryAndGap() { for scenario in [Transport.timeout,.tls,.offline] { let s = Fixtures.session(scenario);#expect(s.incidents.count == 2 && s.gaps.count == 1 && s.sample);#expect(s.checks[1].work?.error == scenario);#expect(s.incidents.allSatisfy { $0.end != nil }) } }
    @Test func referenceFailureSampleIsReachable() { #expect(Fixtures.session(.dns).checks[1].state == .referenceOnly) }
    @Test func missingEvidenceSampleIsReachable() { #expect(Fixtures.session(.unknown).checks[1].state == .insufficient) }
    @Test func accessDenialHasDistinctClassification() { #expect(Transport.classify(URLError(.dataNotAllowed)) == .denied) }
    @Test func historyCodableRoundTrip() throws { let s = Fixtures.session();#expect(try JSONDecoder().decode(Session.self,from:JSONEncoder().encode(s)) == s) }
    @Test func translatedReportRetainsHostnameRedaction() throws {
        let r = try Endpoint.validate("https://reference.example/private?token=SECRET")
        let w = try Endpoint.validate("https://work.example/customer?auth=SECRET")
        let s = Session(name:"PRIVATE PAIR NAME",referenceHost:Endpoint.host(r),workHost:Endpoint.host(w),started:t,sample:false)
        let report = Report.text(s,translate:{ "translated " + $0 })
        #expect(report.contains("reference.example") && report.contains("work.example"))
        #expect(!report.contains("SECRET") && !report.contains("PRIVATE PAIR NAME") && !report.contains("/customer"))
    }

}
