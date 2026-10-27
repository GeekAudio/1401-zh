// Only the forked app's self-update endpoint differs; driver channels remain upstream.
import Foundation

extension App {
    func checkForkAppUpdate() {
        latestApp = nil
        var request = URLRequest(url: URL(string: Downstream.api + "/releases/latest")!)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let fail: (String) -> Void = { self.send("appCheck", ["state": "error", "why": $0]) }
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let payload = try? JSONSerialization.jsonObject(with: data),
                  let release = UpdateChannel.pick(payload, early: false),
                  let assets = release["assets"] as? [[String: Any]] else {
                return fail("无法读取中文 App 的发布列表，请稍后重试。")
            }
            var archive: (String, String, URL)?
            var sums: URL?
            for asset in assets {
                guard let name = asset["name"] as? String,
                      let address = asset["browser_download_url"] as? String,
                      let url = URL(string: address), url.scheme == "https" else { continue }
                if name == "SHA256SUMS.txt" { sums = url }
                if let version = App.releaseAppVersion(name), archive == nil || App.newer(version, than: archive!.0) { archive = (version, name, url) }
            }
            guard let archive, let sums else { return fail("最新发布缺少 App 或校验文件。") }
            URLSession.shared.dataTask(with: sums) { bytes, response, error in
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let bytes,
                      let text = String(data: bytes, encoding: .utf8) else { return fail("无法读取 App 校验文件。") }
                let hash = text.split(separator: "\n").compactMap { line -> String? in
                    let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    return fields.count == 2 && String(fields[1]) == archive.1 ? String(fields[0]).lowercased() : nil
                }.first ?? ""
                let signature = assets.compactMap { asset -> URL? in
                    guard asset["name"] as? String == archive.1 + ".sig",
                          let address = asset["browser_download_url"] as? String,
                          let url = URL(string: address), url.scheme == "https" else { return nil }
                    return url
                }.first
                guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, let signature else { return fail("App 校验信息或更新签名不完整。") }
                DispatchQueue.main.async {
                    self.latestApp = (archive.0, archive.1, archive.2, hash, signature)
                    self.send("appCheck", ["state": "checked", "latest": archive.0, "have": self.appVersion,
                                           "newer": App.newer(archive.0, than: self.appVersion)])
                }
            }.resume()
        }.resume()
    }
}
