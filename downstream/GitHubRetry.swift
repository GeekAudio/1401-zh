import Foundation

/// Retries public GitHub requests through a public-resource proxy after the original URL fails.
/// The original URL is always tried first; callers still validate checksums and signatures.
enum GitHubRetry {
    private static let proxyPrefixes = ["https://gh-proxy.com/"]
    private static let githubHosts: Set<String> = [
        "github.com", "api.github.com", "raw.githubusercontent.com", "objects.githubusercontent.com",
        "release-assets.githubusercontent.com"
    ]

    static func candidates(for url: URL) -> [URL] {
        guard let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host?.lowercased(), githubHosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return [url] }
        return [url] + proxyPrefixes.compactMap { URL(string: $0 + url.absoluteString) }
    }

    static func dataTask(with request: URLRequest, session: URLSession,
                         completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        guard let url = request.url else { return completion(nil, nil, nil) }
        let urls = candidates(for: url)
        dataTask(request, urls: urls, index: 0, session: session, completion: completion)
    }

    static func dataTask(with url: URL, session: URLSession,
                         completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        dataTask(with: request, session: session, completion: completion)
    }

    private static func dataTask(_ request: URLRequest, urls: [URL], index: Int, session: URLSession,
                                 completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        var attempt = request
        attempt.url = urls[index]
        session.dataTask(with: attempt) { data, response, error in
            guard shouldRetry(error: error, response: response), index + 1 < urls.count else {
                return completion(data, response, error)
            }
            dataTask(request, urls: urls, index: index + 1, session: session, completion: completion)
        }.resume()
    }

    static func downloadTask(with url: URL, session: URLSession,
                             validate: @escaping (URL) -> Bool = { _ in true },
                             onRetry: (() -> Void)? = nil,
                             completion: @escaping (URL?, URLResponse?, Error?) -> Void) {
        let urls = candidates(for: url)
        downloadTask(urls, index: 0, session: session, validate: validate, onRetry: onRetry, completion: completion)
    }

    private static func downloadTask(_ urls: [URL], index: Int, session: URLSession,
                                     validate: @escaping (URL) -> Bool, onRetry: (() -> Void)?,
                                     completion: @escaping (URL?, URLResponse?, Error?) -> Void) {
        session.downloadTask(with: urls[index]) { location, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let valid = error == nil && status == 200 && location.map(validate) == true
            guard !valid, index + 1 < urls.count else { return completion(location, response, error) }
            if let location { try? FileManager.default.removeItem(at: location) }
            onRetry?()
            downloadTask(urls, index: index + 1, session: session, validate: validate,
                         onRetry: onRetry, completion: completion)
        }.resume()
    }

    static func syncData(url: URL, timeout: TimeInterval) -> Data? {
        guard url.scheme == "https" else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        for candidate in candidates(for: url) {
            var data: Data?, response: URLResponse?, error: Error?
            let semaphore = DispatchSemaphore(value: 0)
            var request = URLRequest(url: candidate)
            request.timeoutInterval = timeout
            let task = session.dataTask(with: request) { bytes, result, failure in
                data = bytes; response = result; error = failure
                semaphore.signal()
            }
            task.resume()
            if semaphore.wait(timeout: .now() + timeout + 5) == .timedOut {
                task.cancel()
                continue
            }
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data { return data }
        }
        return nil
    }

    private static func shouldRetry(error: Error?, response: URLResponse?) -> Bool {
        if error != nil || response == nil { return true }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return status == 403 || status == 408 || status == 429 || status >= 500
    }
}
