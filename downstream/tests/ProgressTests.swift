import Foundation

func testTaskProgress() {
    var activity = NativeTaskState()
    func task(_ id: String) -> NativeTask? { activity.active.first { $0.id == id } }

    activity.begin(["act": "scan"])
    check(task("scan")?.fraction == nil && activity.at(["machine"]).count == 1, "scan shows indeterminate activity in its panel")
    activity.receive("scan", [:])
    check(activity.active.isEmpty, "scan completion closes activity")

    activity.begin(["act": "checkUpdate"])
    activity.receive("upd", ["state": "error"])
    check(task("driverCheck") == nil && task("appCheck") != nil, "driver check failure does not hide the independent app check")
    activity.receive("appCheck", ["state": "checked"])
    check(activity.active.isEmpty, "both update checks must finish")
    activity.begin(["act": "checkUpdate"])
    activity.receive("appCheck", ["state": "error"])
    check(task("driverCheck") != nil && task("appCheck") == nil, "app check failure does not hide the driver check")
    activity.receive("upd", ["state": "checked"])
    activity.begin(["act": "checkUpdate"])
    activity.begin(["act": "checkUpdate"])
    activity.receive("upd", ["state": "checked"])
    activity.receive("appCheck", ["state": "error"])
    check(activity.active.count == 2, "repeated checks remain active until all outstanding requests finish")
    activity.receive("upd", ["state": "error"])
    activity.receive("appCheck", ["state": "checked"])
    check(activity.active.isEmpty, "last outstanding check closes progress")

    activity.begin(["act": "download"])
    activity.receive("dl", ["state": "progress", "done": 25, "total": 100])
    check(task("download")?.fraction == 0.25, "download fraction uses received byte counts")
    activity.receive("dl", ["state": "progress", "done": 30, "total": -1])
    check(task("download")?.fraction == nil, "unknown content length stays indeterminate")
    activity.receive("dl", ["state": "progress", "done": 100, "total": 100])
    check(task("download") != nil && task("download")?.fraction == nil, "all bytes received is not verification complete")
    activity.receive("dl", ["state": "error"])
    check(activity.active.isEmpty, "download verification failure closes activity")
    activity.begin(["act": "download"], source: "dl3")
    check(activity.at(["updt"]).count == 1, "Tahoe package download stays next to its own button")
    activity.receive("dl", ["state": "done"])
    check(activity.active.isEmpty, "verified ordinary download closes activity")

    activity.begin(["act": "updateDriver"])
    activity.receive("dl", ["state": "start"])
    activity.receive("dl", ["state": "progress", "done": 60, "total": 100])
    check(abs((task("driverUpdate")?.fraction ?? 0) - 0.36) < 0.0001 && task("download") == nil, "driver update reserves total progress for installation")
    activity.receive("dl", ["state": "done"])
    check(task("driverUpdate")?.fraction == 0.6, "driver update continues after its archive downloads")
    activity.receive("run", ["state": "start", "mode": "install"])
    check(activity.active.count == 1 && task("driverUpdate")?.title == "正在安装驱动更新", "driver update transitions to installation")
    activity.receive("taskProgress", ["task": "setup", "fraction": 0.5])
    check(task("driverUpdate")?.fraction == 0.8, "installer stages continue overall update progress")
    activity.receive("taskProgress", ["task": "setup", "fraction": 0.2])
    check(task("driverUpdate")?.fraction == 0.8, "late notifications never move progress backwards")
    activity.receive("run", ["state": "cancelled", "mode": "install"])
    check(activity.active.isEmpty, "cancelled authorization closes driver update progress")
    activity.begin(["act": "updateDriver"])
    activity.receive("upd", ["state": "error"])
    check(activity.active.isEmpty, "update without a release does not leave progress running")

    activity.begin(["act": "gputest", "on": true])
    activity.receive("dl", ["state": "start"])
    check(activity.active.count == 1 && activity.at(["gpuon"]).count == 1, "test driver download stays with its original tool")
    activity.receive("run", ["state": "start", "mode": "verbose"])
    activity.receive("run", ["state": "end", "mode": "verbose", "ok": false])
    check(activity.active.isEmpty, "test driver failure closes its activity")

    for command: [String: Any] in [
        ["act": "run", "mode": "dry"], ["act": "run", "mode": "install"], ["act": "run", "mode": "remove"],
        ["act": "verbose"], ["act": "backlight"], ["act": "gputest", "on": false],
        ["act": "osupdate", "pkg": "/tmp/driver.tar.gz"], ["act": "osupdate", "cancel": true], ["act": "usbWrite"]
    ] {
        activity.begin(command)
        check(task("setup") != nil, "setup operation is represented: \(command)")
        activity.receive("run", ["state": "end", "ok": false])
        check(activity.active.isEmpty, "failed setup stops progress: \(command)")
    }
    activity.begin(["act": "run", "mode": "install"], setupRunning: true)
    activity.begin(["act": "verbose"], downloadPending: true)
    activity.begin(["act": "osupdate", "pkg": ""])
    check(activity.active.isEmpty, "ignored or unavailable setup does not invent progress")
    activity.begin(["act": "usbWrite"])
    activity.receive("usbErr", "invalid map")
    check(activity.active.isEmpty, "map generation failure closes progress before setup starts")

    activity.begin(["act": "updateApp"])
    activity.receive("appupd", ["state": "start"])
    check(task("appUpdate")?.fraction == 0, "app update starts at zero without estimated time progress")
    activity.receive("taskProgress", ["task": "appUpdate", "fraction": 0.85])
    check(task("appUpdate")?.fraction == 0.85, "app verification stages show percentage progress")
    activity.receive("appupd", ["state": "restarting"])
    check(task("appUpdate") != nil, "app progress remains visible through relaunch")
    activity.receive("appupd", ["state": "error"])
    check(activity.active.isEmpty, "app verification error closes progress")

    activity.begin(["act": "mountEfi"])
    check(activity.active.isEmpty, "EFI mounting has no progress bar or navigation activity indicator")
    for (action, event) in [("checkEfi", "efiCheck")] {
        activity.begin(["act": action])
        check(activity.active.count == 1, "EFI operation starts activity")
        activity.receive(event, ["cancelled": true])
        check(activity.active.isEmpty, "cancelled EFI operation closes activity")
    }

    activity.begin(["act": "gpumap"])
    activity.receive("gpumapStatus", ["text": "Measuring (1 of 5): identity..."])
    check(task("gpuMap")?.fraction == 0, "GPU measurement does not count an unfinished first stage")
    activity.receive("gpumapStatus", ["text": "Measuring (3 of 5): bench..."])
    check(task("gpuMap")?.fraction == 0.4, "GPU measurement counts completed stages")
    activity.receive("gpumapStatus", ["text": "Measuring (5 of 5): displays and driver state..."])
    check(task("gpuMap")?.fraction == 0.8, "final GPU stage is not reported as already complete")
    activity.receive("gpumapStatus", ["done": true])
    activity.receive("logsStatus", ["text": "Waiting for your Mac password (a macOS window asks for it). Collecting takes a few minutes; 1401 keeps working."])
    check(task("gpuMap") == nil && task("logs") != nil, "GPU completion followed by original log collection is observed")
    activity.receive("logsDone", ["ok": false])
    check(activity.active.isEmpty, "log collection cancellation closes activity")

    activity.begin(["act": "sendLogs", "sample": "flicker"], source: "fl")
    check(activity.at(["sl", "fl"]).count == 1 && task("logs")?.fraction == 0, "flicker recording starts at zero without a fabricated timer")
    activity.receive("taskProgress", ["task": "logs", "fraction": 0.35])
    check(task("logs")?.fraction == 0.35 && task("logs")?.basis == "阶段进度", "actual collector checkpoints advance log progress")
    activity.receive("taskProgress", ["task": "logs", "fraction": 0.87, "completed": 8, "total": 16])
    check(task("logs")?.fraction == 0.87 && task("logs")?.amount == "已处理 8 / 16 份", "upload progress is based on processed reports")
    activity.receive("taskProgress", ["task": "logs", "fraction": 0.35])
    check(task("logs")?.title == "正在发送日志" && task("logs")?.fraction == 0.87, "late collector milestones cannot restore an earlier phase label")
    activity.receive("taskProgress", ["task": "logs", "fraction": 1.0])
    check(task("logs")?.fraction == 0.87, "notification cannot claim completion before the original result")
    activity.receive("logsStatus", ["text": "Sending..."])
    activity.receive("logsDone", ["ok": true])
    check(activity.active.isEmpty, "successful log upload closes activity")
    activity.receive("taskProgress", ["task": "logs", "fraction": 0.95])
    check(activity.active.isEmpty, "late progress cannot revive a completed or cancelled operation")

    activity.begin(["act": "optionalDiagnostics"])
    activity.receive("diagnosticsStatus", ["text": "Checking availability. No trace starts."])
    check(task("diagnostics") != nil, "diagnostics initial status does not prematurely finish progress")
    activity.receive("diagnosticsStatus", ["text": "Trace capture is unavailable in this build."])
    check(activity.active.isEmpty, "diagnostics result closes activity")

    activity.begin(["act": "usbStart"])
    activity.receive("usb", ["controllers": []])
    check(task("usbWatch") == nil && activity.active.isEmpty, "USB monitoring has no progress bar or navigation activity indicator")
    activity.begin(["act": "usbStop"])
    check(activity.active.isEmpty, "USB stop or page navigation closes monitoring activity")

    let bridge = NativeModel()
    var dispatched = [[String: Any]]()
    bridge.action = { command in
        bridge.tasks.begin(command, source: bridge.taskSource)
        dispatched.append(command)
    }
    bridge.press("vboff")
    check(bridge.tasks.at(["vboff"]).count == 1 && bridge.taskSource == nil, "button origin is presentation-only and scoped to dispatch")
    check(dispatched.count == 1 && dispatched[0]["act"] as? String == "verbose" && dispatched[0]["on"] as? Bool == false, "progress never adds commands or changes the original action")
    bridge.receive("run", ["state": "cancelled", "mode": "verbose"])
    check(bridge.tasks.active.allSatisfy { $0.id == "scan" }, "original rescan after cancellation is tracked independently")

    // Exercise the same script-side publisher and public native notification API without running setup.
    var values: [Double] = []
    let session = NativeProgressSession { values.append($0) }
    let script = try! String(contentsOfFile: "mac/Resources/nullmoth-setup.sh", encoding: .utf8)
    let start = script.range(of: "# BEGIN GEEKAUDIO PRESENTATION PROGRESS")!.lowerBound
    let end = script.range(of: "# END GEEKAUDIO PRESENTATION PROGRESS")!.upperBound
    let support = String(script[start..<end])
    let publisher = Process()
    publisher.executableURL = URL(fileURLWithPath: "/bin/bash")
    publisher.arguments = ["-c", support + "\ndownstream_progress_step 'OpenCore config updated'"]
    publisher.environment = ProcessInfo.processInfo.environment.merging(["GEEK_PROGRESS_CHANNEL": session.channel]) { _, value in value }
    try! publisher.run(); publisher.waitUntilExit()
    let deadline = Date().addingTimeInterval(3)
    while values.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    check(publisher.terminationStatus == 0 && values.last == 0.75, "installer milestone reaches the app over the native progress channel")
    let rootCheck = Process(); rootCheck.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    rootCheck.arguments = ["-n", "/usr/bin/true"]; rootCheck.standardError = FileHandle.nullDevice
    try! rootCheck.run(); rootCheck.waitUntilExit()
    if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
        check(rootCheck.terminationStatus == 0, "CI must verify privileged progress delivery")
    }
    if rootCheck.terminationStatus == 0 {
        let rootPublisher = Process(); rootPublisher.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        rootPublisher.arguments = ["-n", "/usr/bin/notifyutil", "-q", "-z", "0", "-s", session.channel, "93", "-p", session.channel]
        try! rootPublisher.run(); rootPublisher.waitUntilExit()
        let rootDeadline = Date().addingTimeInterval(3)
        while values.last != 0.93 && Date() < rootDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        check(rootPublisher.terminationStatus == 0 && values.last == 0.93, "privileged publisher can report numeric progress to the user app")
    } else { print("Privileged notification check skipped: noninteractive sudo unavailable; no authorization requested") }
    session.close()
    let previous = values.count
    let late = Process(); late.executableURL = URL(fileURLWithPath: "/usr/bin/notifyutil")
    late.arguments = ["-q", "-z", "0", "-s", session.channel, "90", "-p", session.channel]
    try! late.run(); late.waitUntilExit()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    check(values.count == previous, "finished progress session unregisters its native callback")
}
