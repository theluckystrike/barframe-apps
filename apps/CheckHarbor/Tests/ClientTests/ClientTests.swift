import Foundation
import Testing
@testable import CheckHarbor
import CheckHarborCore
final class FailedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
final class UnauthorizedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:401,httpVersion:nil,headerFields:[:])!,cacheStoragePolicy:.notAllowed); client?.urlProtocolDidFinishLoading(self) }
    override func stopLoading() {}
}
@MainActor @Test func failedNetworkPreservesEpisodes() async {
    let c=URLSessionConfiguration.ephemeral; c.protocolClasses=[FailedProtocol.self]
    let m=Model(ephemeral:true,session:URLSession(configuration:c),tokenProvider:{nil})
    m.repositories=["harbor/demo"]; m.state.inbox.ingest(repository:"harbor/demo",runs:Fixtures.initial)
    let before=m.state.inbox; await m.refresh()
    #expect(m.state.inbox == before); #expect(m.errors["harbor/demo"] != nil); #expect(m.stale)
}
@MainActor @Test func unauthorizedPreservesEpisodes() async {
    let c=URLSessionConfiguration.ephemeral; c.protocolClasses=[UnauthorizedProtocol.self]
    let m=Model(ephemeral:true,session:URLSession(configuration:c),tokenProvider:{nil})
    m.repositories=["harbor/demo"]; m.state.inbox.ingest(repository:"harbor/demo",runs:Fixtures.initial)
    let before=m.state.inbox; await m.refresh()
    #expect(m.state.inbox == before); #expect(m.errors["harbor/demo"]?.contains("Authentication") == true)
}
@MainActor @Test func sampleRefreshNeverReadsCredentials() async {
    var reads=0
    let m=Model(ephemeral:true,tokenProvider:{ reads += 1; return nil })
    m.repositories=["harbor/demo"]; m.toggleSample(true)
    let before=m.state.inbox; await m.refresh()
    #expect(reads == 0); #expect(m.state.inbox == before); #expect(m.errors.isEmpty)
}
@MainActor @Test func backoffStopsBeforeCredentials() async {
    var reads=0; let m=Model(ephemeral:true,tokenProvider:{ reads += 1; return nil })
    m.repositories=["harbor/demo"]; m.state.backoff = .distantFuture; await m.refresh()
    #expect(reads == 0); #expect(m.stale)
}
@Test func redirectIsRejected() {
    let d=NoRedirect(); var redirected: URLRequest?=URLRequest(url:URL(string:"https://evil.test")!)
    d.urlSession(URLSession.shared,task:URLSession.shared.dataTask(with:URL(string:"https://api.github.com")!),willPerformHTTPRedirection:HTTPURLResponse(url:URL(string:"https://api.github.com")!,statusCode:302,httpVersion:nil,headerFields:[:])!,newRequest:redirected!) { redirected=$0 }
    #expect(redirected == nil)
}

@Test func provisionalHelpUsesLocalText() {
    #expect(HelpDestination.url("https://{DOMAIN}/apps/checkharbor/privacy/") == nil)
    #expect(HelpDestination.url(nil) == nil)
    #expect(LocalHelp.privacy.text.contains("Unresolved episodes"))
    #expect(LocalHelp.privacy.text.contains("7, 30 or 90 days"))
    #expect(LocalHelp.support.text.contains("Try Sample"))
}
@Test func finalizedHelpCanOpenWebsite() {
    #expect(HelpDestination.url("https://barframe.com/apps/checkharbor/privacy/")?.host == "barframe.com")
    #expect(HelpDestination.url("http://barframe.com/apps/checkharbor/support/") == nil)
}

@Test func helpDestinationMustMatchItsPolicyPath() {
    #expect(HelpDestination.url("https://barframe.com/apps/checkharbor/privacy/",path:"/apps/checkharbor/privacy/") != nil)
    #expect(HelpDestination.url("https://barframe.com/apps/checkharbor/support/",path:"/apps/checkharbor/privacy/") == nil)
}
