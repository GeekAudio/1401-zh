import Foundation

final class UpdateFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> (Int, Data))?
    private static var requested: [URL] = []
    private static var resolved: ((URLRequest) -> URL)?

    static func configure(resolved: ((URLRequest) -> URL)? = nil, _ value: @escaping (URLRequest) -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        handler = value; requested = []
        Self.resolved = resolved
    }
    static var requests: [URL] { lock.lock(); defer { lock.unlock() }; return requested }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requested.append(request.url!)
        let handler = Self.handler!
        let resolved = Self.resolved
        Self.lock.unlock()
        let (status, data) = handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: resolved?(request) ?? request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func testUpdateClient() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UpdateFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let name = "1401-Mac-2.6.4.24.zip"
    let base = "https://github.com/GeekAudio/1401-zh/releases/download/v2.6.4.24/"
    let assets = [name, name + ".sig", "SHA256SUMS.txt"].map { ["name": $0, "browser_download_url": base + $0] }
    var release: [String: Any] = ["tag_name": "v2.6.4.24", "draft": false, "prerelease": false, "assets": assets]
    let sum = String(repeating: "a", count: 64) + "  " + name + "\n"

    func waitFor(_ done: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !done() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(done(), "update client completes within its test bound")
    }
    func fixture(apiStatus: Int = 200, checksumStatus: Int = 200, checksum: String? = nil) {
        let document = try! JSONSerialization.data(withJSONObject: release)
        UpdateFixtureProtocol.configure { request in
            if request.url!.host == "api.github.com" { return (apiStatus, document) }
            return (checksumStatus, Data((checksum ?? sum).utf8))
        }
    }
    fixture()
    let shared = AppUpdateClient(session: session)
    var result: Result<AppUpdateRelease, Error>?
    var callbacks = 0
    shared.check { result = $0; callbacks += 1 }
    shared.check { result = $0; callbacks += 1 }
    waitFor { callbacks == 2 }
    check(UpdateFixtureProtocol.requests.count == 2, "manual and auto checks share one API request and one checksum request")
    if case .success(let update) = result {
        check(update.version == "2.6.4.24" && update.name == name && update.sha256.count == 64, "real client returns the verified release plan")
    } else { check(false, "valid release must be accepted") }
    check(UpdateFixtureProtocol.requests[0].absoluteString == "https://api.github.com/repos/GeekAudio/1401-zh/releases/latest", "automatic check reaches only our app release endpoint")

    func expectFailure(_ label: String) {
        var outcome: Result<AppUpdateRelease, Error>?
        let client = AppUpdateClient(session: session)
        client.check { outcome = $0 }
        waitFor { outcome != nil }
        if case .failure = outcome { check(true, label) } else { check(false, label) }
    }
    fixture(apiStatus: 403); expectFailure("rate limit with an unavailable public release cannot start an update")
    fixture(checksumStatus: 404); expectFailure("missing checksums cannot start an update")
    fixture(checksum: "invalid  " + name); expectFailure("malformed SHA cannot start an update")
    release["draft"] = true; fixture(); expectFailure("automatic updates reject draft releases")
    release["draft"] = false; release["prerelease"] = true; fixture(); expectFailure("automatic updates reject prereleases")
    release["prerelease"] = false
    release["assets"] = assets.filter { $0["name"] != name + ".sig" }; fixture(); expectFailure("automatic updates require a detached signature")
    release["assets"] = assets.map { row -> [String: String] in
        var row = row
        if row["name"] == name { row["browser_download_url"] = "https://github.com/another/repository/releases/download/v1/" + name }
        return row
    }
    fixture(); expectFailure("automatic updates reject archives hosted outside our GitHub repository")

    UpdateFixtureProtocol.configure(resolved: { request in
        request.url!.path.hasSuffix("/releases/latest") && request.url!.host == "github.com"
            ? URL(string: "https://github.com/GeekAudio/1401-zh/releases/tag/v2.6.4.24")! : request.url!
    }) { request in
        if request.url!.host == "api.github.com" { return (403, Data()) }
        return (200, Data((sum + String(repeating: "b", count: 64) + "  " + name + ".sig\n").utf8))
    }
    var publicResult: Result<AppUpdateRelease, Error>?
    let publicClient = AppUpdateClient(session: session)
    publicClient.check { publicResult = $0 }
    waitFor { publicResult != nil }
    if case .success(let update) = publicResult {
        check(update.version == "2.6.4.24" && update.url.absoluteString == base + name, "API rate limit falls back to a fixed public release tag")
    } else { check(false, "valid public release must survive API rate limits") }
    check(UpdateFixtureProtocol.requests.count == 3, "public fallback is bounded to one redirect check and one checksum read")
}
