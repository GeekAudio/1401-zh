import Foundation

// Shared by manual and automatic checks; coalescing keeps responses in one order.
final class AppUpdateClient {
    typealias Completion = (Result<AppUpdateRelease, Error>) -> Void
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private let session: URLSession
    private let repository: String
    private var completions: [Completion] = []

    init(session: URLSession = .shared, repository: String = Downstream.repository) {
        self.session = session; self.repository = repository
    }

    func check(_ completion: @escaping Completion) {
        precondition(Thread.isMainThread)
        completions.append(completion)
        guard completions.count == 1 else { return }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/" + repository + "/releases/latest")!)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("1401-zh-app-updater", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil || code == 403 || code == 429 || code >= 500 { return self.checkPublicRelease() }
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let payload = try? JSONSerialization.jsonObject(with: data),
                  let release = UpdateChannel.pick(payload, early: false),
                  let assets = release["assets"] as? [[String: Any]] else {
                return self.fail("无法读取中文 App 的发布列表，请稍后重试。")
            }
            var archive: (version: String, name: String, url: URL)?
            var sums: URL?
            for asset in assets {
                guard let name = asset["name"] as? String, let url = self.assetURL(asset, name: name) else { continue }
                if name == "SHA256SUMS.txt" { sums = url }
                if let version = AppUpdateRelease.version(in: name), archive == nil || UpdateChannel.newer(version, than: archive!.version) {
                    archive = (version, name, url)
                }
            }
            guard let archive, let sums else { return self.fail("最新发布缺少 App 或校验文件。") }
            var checksumRequest = URLRequest(url: sums)
            checksumRequest.timeoutInterval = 30
            checksumRequest.cachePolicy = .reloadIgnoringLocalCacheData
            self.session.dataTask(with: checksumRequest) { bytes, response, error in
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let bytes,
                      let text = String(data: bytes, encoding: .utf8) else { return self.fail("无法读取 App 校验文件。") }
                let hash = text.split(separator: "\n").compactMap { line -> String? in
                    let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    return fields.count == 2 && String(fields[1]) == archive.name ? String(fields[0]).lowercased() : nil
                }.first ?? ""
                let signature = assets.first { $0["name"] as? String == archive.name + ".sig" }
                    .flatMap { self.assetURL($0, name: archive.name + ".sig") }
                guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, let signature else {
                    return self.fail("App 校验信息或更新签名不完整。")
                }
                self.finish(.success(AppUpdateRelease(version: archive.version, name: archive.name, url: archive.url, sha256: hash, signature: signature)))
            }.resume()
        }.resume()
    }

    // Public release redirects do not consume the unauthenticated API allowance.
    // Resolve a fixed tag before reading sums so a new release cannot mix assets.
    private func checkPublicRelease() {
        var request = URLRequest(url: URL(string: "https://github.com/" + repository + "/releases/latest")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: request) { _, response, error in
            let prefix = "/" + self.repository + "/releases/tag/"
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let url = response?.url,
                  url.scheme == "https", url.host?.lowercased() == "github.com", url.path.hasPrefix(prefix) else {
                return self.fail("无法读取中文 App 的公开发布页，请稍后重试。")
            }
            let tag = String(url.path.dropFirst(prefix.count))
            guard tag.range(of: #"^v?[0-9]+(?:\.[0-9]+){1,3}$"#, options: .regularExpression) != nil else {
                return self.fail("公开发布页的版本信息无效。")
            }
            let base = URL(string: "https://github.com/" + self.repository + "/releases/download/" + tag + "/")!
            var request = URLRequest(url: base.appendingPathComponent("SHA256SUMS.txt"))
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            self.session.dataTask(with: request) { bytes, response, error in
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let bytes,
                      let text = String(data: bytes, encoding: .utf8) else { return self.fail("无法读取 App 校验文件。") }
                var hashes = [String: String]()
                for line in text.split(separator: "\n") {
                    let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    guard fields.count == 2, fields[0].range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { continue }
                    hashes[String(fields[1])] = String(fields[0]).lowercased()
                }
                let names = hashes.keys.filter { AppUpdateRelease.version(in: $0) != nil }
                guard let name = names.max(by: { UpdateChannel.newer(AppUpdateRelease.version(in: $1)!, than: AppUpdateRelease.version(in: $0)!) }),
                      let version = AppUpdateRelease.version(in: name), let hash = hashes[name], hashes[name + ".sig"] != nil else {
                    return self.fail("App 校验信息或更新签名不完整。")
                }
                self.finish(.success(AppUpdateRelease(version: version, name: name, url: base.appendingPathComponent(name), sha256: hash, signature: base.appendingPathComponent(name + ".sig"))))
            }.resume()
        }.resume()
    }

    private func assetURL(_ asset: [String: Any], name: String) -> URL? {
        guard let address = asset["browser_download_url"] as? String, let url = URL(string: address),
              url.scheme == "https", url.host?.lowercased() == "github.com", url.user == nil, url.password == nil,
              url.port == nil, url.path.hasPrefix("/" + repository + "/releases/download/"),
              url.lastPathComponent == name else { return nil }
        return url
    }

    private func fail(_ message: String) { finish(.failure(Failure(message: message))) }
    private func finish(_ result: Result<AppUpdateRelease, Error>) {
        DispatchQueue.main.async {
            let callbacks = self.completions
            self.completions.removeAll()
            callbacks.forEach { $0(result) }
        }
    }
}
