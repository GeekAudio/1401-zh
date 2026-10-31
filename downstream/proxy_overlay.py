"""Reversible GitHub proxy retries that leave update/install policy unchanged."""


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise RuntimeError('GitHub retry overlay anchor changed: ' + before[:100])
    return source.replace(before, after)


EDITS = [
    ('''func syncGet(_ url: URL, timeout: TimeInterval) -> Data? {
    guard url.scheme == "https" else { return nil }
    var out: Data? = nil
    let sem = DispatchSemaphore(value: 0)
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeout
    let session = URLSession(configuration: config)
    var rq = URLRequest(url: url); rq.timeoutInterval = timeout
    session.dataTask(with: rq) { d, resp, _ in
        if (resp as? HTTPURLResponse)?.statusCode == 200 { out = d }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + timeout + 5)
    session.finishTasksAndInvalidate()
    return out
}''',
     '''func syncGet(_ url: URL, timeout: TimeInterval) -> Data? {
    guard url.scheme == "https" else { return nil }
    return GitHubRetry.syncData(url: url, timeout: timeout)
}'''),
    ('''    struct DownloadPlan {
        let name: String
        let sha: String
        let efi: String?
    }''',
     '''    struct DownloadPlan {
        let name: String
        let sha: String
        let efi: String?
        let retryURLs: [URL]
        init(name: String, sha: String, efi: String?, retryURLs: [URL] = []) {
            self.name = name; self.sha = sha; self.efi = efi; self.retryURLs = retryURLs
        }
    }'''),
    ('''        let task = downloadSession.downloadTask(with: url)
        pendingDownload = (task.taskIdentifier, DownloadPlan(name: name, sha: sha, efi: efi))''',
     '''        let urls = GitHubRetry.candidates(for: url)
        let task = downloadSession.downloadTask(with: urls[0])
        pendingDownload = (task.taskIdentifier, DownloadPlan(name: name, sha: sha, efi: efi, retryURLs: Array(urls.dropFirst())))'''),
    ('''        URLSession.shared.dataTask(with: rq) { data, resp, err in
            let fail: (String) -> Void = { self.send("upd", ["state": "error", "why": $0]) }''',
     '''        GitHubRetry.dataTask(with: rq, session: .shared) { data, resp, err in
            let fail: (String) -> Void = { self.send("upd", ["state": "error", "why": $0]) }'''),
    ('''            URLSession.shared.dataTask(with: sums) { sd, sr, se in''',
     '''            GitHubRetry.dataTask(with: sums, session: .shared) { sd, sr, se in'''),
    ('''            }.resume()
        }.resume()
    }
    func startDownload(name: String, sha: String, url: URL, efi: String?) {''',
     '''            }
        }
    }
    func startDownload(name: String, sha: String, url: URL, efi: String?) {'''),
    ('''        URLSession.shared.downloadTask(with: l.url) { loc, resp, err in''',
     '''        GitHubRetry.downloadTask(with: l.url, session: .shared, validate: { sha256($0) == l.sha },
                                  onRetry: { self.send("appupd", ["state": "retry", "version": l.version]) }) { loc, resp, err in'''),
    ('''    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData b: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {''',
     '''    private func retryDriverDownload(_ pending: (id: Int, plan: DownloadPlan)) -> Bool {
        guard let next = pending.plan.retryURLs.first else { return false }
        let nextPlan = DownloadPlan(name: pending.plan.name, sha: pending.plan.sha, efi: pending.plan.efi,
                                    retryURLs: Array(pending.plan.retryURLs.dropFirst()))
        let task = downloadSession.downloadTask(with: next)
        pendingDownload = (task.taskIdentifier, nextPlan)
        send("dl", ["state": "retry"])
        task.resume()
        return true
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData b: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {'''),
    ('''        }.resume()
    }
    private func retryDriverDownload(_ pending: (id: Int, plan: DownloadPlan)) -> Bool {''',
     '''        }
    }
    private func retryDriverDownload(_ pending: (id: Int, plan: DownloadPlan)) -> Bool {'''),
    ('''        let code = (t.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { send("dl", ["state": "error", "why": "the server answered HTTP \\(code)"]); return }
        processDriverFile(at: loc, plan: plan)''',
     '''        let code = (t.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            if retryDriverDownload(pending) { return }
            pendingDownload = nil
            send("dl", ["state": "error", "why": "the server answered HTTP \\(code)"]); return
        }
        guard sha256(loc) == plan.sha else {
            if retryDriverDownload(pending) { return }
            pendingDownload = nil
            send("dl", ["state": "error", "why": "the download does not match its SHA-256, so it was thrown away"]); return
        }
        processDriverFile(at: loc, plan: plan)'''),
    ('''    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        guard pendingDownload?.id == task.taskIdentifier else { return }
        pendingDownload = nil
        if let e { send("dl", ["state": "error", "why": e.localizedDescription]) }
    }''',
     '''    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        guard let pending = pendingDownload, pending.id == task.taskIdentifier, let e else { return }
        if retryDriverDownload(pending) { return }
        pendingDownload = nil
        send("dl", ["state": "error", "why": e.localizedDescription])
    }'''),
]


def instrument(source):
    for before, after in EDITS:
        source = replace_once(source, before, after)
    return source


def strip(source):
    for before, after in reversed(EDITS):
        source = replace_once(source, after, before)
    return source
