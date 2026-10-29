import Foundation

// Main-thread scheduling only. Download, verification and replacement stay in updateApp().
final class AutomaticAppUpdates {
    enum Phase { case idle, requested, updating, committing }
    private(set) var phase: Phase = .idle
    private(set) var checking = false
    private var attempted: [String: Date] = [:]
    private var pendingVersion: String?
    private var replacement: (() -> Void)?
    private var logOperations = 0
    private var timer: Timer?
    private var currentVersion = ""
    private var nextCheck = Date.distantFuture
    private var check: (@escaping (String?) -> Void) -> Void = { $0(nil) }
    private var isIdle: () -> Bool = { false }
    private var install: () -> Void = {}
    private let clock: () -> Date
    private let interval: TimeInterval

    init(interval: TimeInterval = 60 * 60, clock: @escaping () -> Date = Date.init) {
        self.interval = interval; self.clock = clock
    }

    func start(version: String, check: @escaping (@escaping (String?) -> Void) -> Void,
               isIdle: @escaping () -> Bool, install: @escaping () -> Void, scheduleTimer: Bool = true) {
        precondition(Thread.isMainThread)
        guard timer == nil, currentVersion.isEmpty else { return }
        currentVersion = version
        self.check = check; self.isIdle = isIdle; self.install = install
        nextCheck = clock().addingTimeInterval(5)
        if scheduleTimer {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func poll() {
        precondition(Thread.isMainThread)
        if let action = replacement {
            guard logOperations == 0, isIdle() else { return }
            replacement = nil
            phase = .committing
            action()
            return
        }
        guard phase == .idle else { return }
        if let version = pendingVersion, mayAttempt(version), logOperations == 0, isIdle() {
            pendingVersion = nil
            attempted[version] = clock()
            phase = .requested
            install()
            return
        }
        guard !checking, clock() >= nextCheck else { return }
        checking = true
        nextCheck = clock().addingTimeInterval(interval)
        check { [weak self] version in
            guard let self else { return }
            self.checking = false
            self.offer(version)
        }
    }

    func offer(_ version: String?) {
        precondition(Thread.isMainThread)
        guard let version, UpdateChannel.newer(version, than: currentVersion), mayAttempt(version) else {
            pendingVersion = nil
            return
        }
        pendingVersion = version
    }

    func beginUpdate(version: String?) -> Bool {
        precondition(Thread.isMainThread)
        guard phase == .idle || phase == .requested else { return false }
        phase = .updating; pendingVersion = nil
        if let version { attempted[version] = clock() }
        return true
    }

    func replaceWhenIdle(_ action: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        replacement = action
        poll()
    }

    func failed() {
        precondition(Thread.isMainThread)
        replacement = nil; phase = .idle
        nextCheck = max(nextCheck, clock().addingTimeInterval(interval))
    }

    func logsStarted() { precondition(Thread.isMainThread); logOperations += 1 }
    func logsFinished() { precondition(Thread.isMainThread); logOperations = max(0, logOperations - 1) }
    private func mayAttempt(_ version: String) -> Bool {
        attempted[version].map { clock().timeIntervalSince($0) >= interval } ?? true
    }
    deinit { timer?.invalidate() }
}
