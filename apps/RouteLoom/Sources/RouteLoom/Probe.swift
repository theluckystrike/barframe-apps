import Foundation
import RouteLoomCore

final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum Probe {
    static func configuration(timeout: Double) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.urlCredentialStorage = nil
        c.httpShouldSetCookies = false
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout
        return c
    }
    static func request(_ url: URL, timeout: Double) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        r.httpMethod = "HEAD"
        r.httpShouldHandleCookies = false
        r.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        r.setValue("RouteLoom", forHTTPHeaderField: "User-Agent")
        return r
    }
    static func observe(_ url: URL, timeout: Double) async -> Observation {
        let at = Date()
        let start = ContinuousClock.now
        let session = URLSession(configuration: configuration(timeout: timeout), delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(for: request(url, timeout:timeout))
            let d = start.duration(to: .now).components
            return Observation(at:at,elapsed:Double(d.seconds) + Double(d.attoseconds)/1e18,status:(response as? HTTPURLResponse)?.statusCode)
        } catch {
            let d = start.duration(to: .now).components
            return Observation(at:at,elapsed:Double(d.seconds) + Double(d.attoseconds)/1e18,error:Transport.classify(error))
        }
    }
    static func pair(_ reference: URL, _ work: URL, _ timeout: Double) async -> PairCheck {
        let at = Date()
        async let r = observe(reference,timeout:timeout)
        async let w = observe(work,timeout:timeout)
        return await PairCheck(at:at,reference:r,work:w)
    }
}
