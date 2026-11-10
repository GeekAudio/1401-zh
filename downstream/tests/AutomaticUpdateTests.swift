import Foundation

func testAutomaticUpdates() {
    var restartGate = AppUpdateIdleState()
    check(restartGate.canReplaceApp, "an idle app can be replaced")
    restartGate.gameModeBusy = true
    check(!restartGate.canReplaceApp, "Game Mode authorization blocks app replacement")
    restartGate.gameModeBusy = false; restartGate.settingsPanelOpen = true
    check(!restartGate.canReplaceApp, "an open driver settings panel blocks app replacement")
    restartGate.settingsPanelOpen = false; restartGate.settingsBusy = true
    check(!restartGate.canReplaceApp, "background driver-settings authorization blocks app replacement")
    restartGate.settingsBusy = false; restartGate.activeTaskIDs = ["appUpdate", "setup"]
    check(!restartGate.canReplaceApp, "an active setup task blocks app replacement")
    restartGate.activeTaskIDs = ["appUpdate"]; restartGate.modalWindowOpen = true
    check(!restartGate.canReplaceApp, "an authorization sheet blocks app replacement")

    var now = Date(timeIntervalSince1970: 1000)
    var idle = false, checks = 0, installs = 0, replacements = 0
    var checked: ((String?) -> Void)?
    let updates = AutomaticAppUpdates(interval: 3600, clock: { now })
    updates.start(version: "2.6.4.23", check: { checks += 1; checked = $0 }, isIdle: { idle }, install: {
        installs += 1
        check(updates.beginUpdate(version: "2.6.4.24"), "scheduled update acquires one download lock")
    }, scheduleTimer: false)
    updates.poll()
    check(checks == 0, "startup waits for the window to initialize")
    now += 5; updates.poll(); updates.poll()
    check(checks == 1 && updates.checking, "startup performs one app-only check")
    checked?("2.6.4.23"); updates.poll()
    check(installs == 0, "current release is never installed again")
    now += 3600; updates.poll()
    check(checks == 2, "running app checks again after the hourly interval")
    checked?("2.6.4.24"); updates.poll()
    check(installs == 0, "new release waits while existing work runs")
    idle = true; updates.poll(); updates.poll()
    check(installs == 1 && updates.phase == .updating, "new release automatically downloads exactly once when idle")
    check(!updates.beginUpdate(version: "2.6.4.24"), "concurrent manual click cannot start a second download")
    idle = false
    updates.replaceWhenIdle { replacements += 1 }
    check(replacements == 0, "work started during download delays replacement")
    updates.logsStarted(); idle = true; updates.poll()
    check(replacements == 0, "direct GPU-to-log continuation blocks restart before log status arrives")
    updates.logsFinished(); updates.poll(); updates.poll()
    check(replacements == 1 && updates.phase == .committing, "validated app is replaced once after all work ends")
    check(!updates.beginUpdate(version: "2.6.4.24"), "no duplicate swap while the app is quitting")

    var operationGate = AppUpdateIdleState()
    var gatedReplacements = 0
    let gated = AutomaticAppUpdates(interval: 3600, clock: { now })
    gated.start(version: "2.6.4.23", check: { $0(nil) }, isIdle: { operationGate.canReplaceApp }, install: {
        _ = gated.beginUpdate(version: "2.6.4.24")
    }, scheduleTimer: false)
    operationGate.gameModeBusy = true
    gated.replaceWhenIdle { gatedReplacements += 1 }
    check(gatedReplacements == 0, "a verified update waits while Game Mode authorization is active")
    operationGate.gameModeBusy = false; operationGate.settingsPanelOpen = true; gated.poll()
    check(gatedReplacements == 0, "a verified update waits while the settings window is open")
    operationGate.settingsPanelOpen = false; operationGate.settingsBusy = true; gated.poll()
    check(gatedReplacements == 0, "a verified update waits after the settings window closes during authorization")
    operationGate.settingsBusy = false; gated.poll()
    check(gatedReplacements == 1, "app replacement continues once Game Mode and settings authorization are idle")

    let retry = AutomaticAppUpdates(interval: 3600, clock: { now })
    var retryInstalls = 0
    retry.start(version: "2.6.4.23", check: { $0(nil) }, isIdle: { true }, install: {
        retryInstalls += 1
        _ = retry.beginUpdate(version: "2.6.4.24")
    }, scheduleTimer: false)
    retry.offer("2.6.4.24"); retry.poll(); retry.failed()
    retry.offer("2.6.4.24"); retry.poll()
    check(retryInstalls == 1, "failed verification or download does not create an immediate retry loop")
    check(retry.beginUpdate(version: "2.6.4.24"), "manual retry remains available after failure")
    retry.failed(); now += 3600
    retry.offer("2.6.4.24"); retry.poll()
    check(retryInstalls == 2, "temporary failures may retry after the normal hourly check")

    let withdrawn = AutomaticAppUpdates(clock: { now })
    var withdrawnInstalls = 0
    withdrawn.start(version: "2.6.4.23", check: { $0(nil) }, isIdle: { true }, install: { withdrawnInstalls += 1 }, scheduleTimer: false)
    withdrawn.offer("2.6.4.25"); withdrawn.offer(nil); withdrawn.poll()
    check(withdrawnInstalls == 0, "latest check can withdraw a previously offered update")
    withdrawn.offer("2.6.4.22"); withdrawn.poll()
    check(withdrawnInstalls == 0, "automatic updates never downgrade")
    check(AppUpdateRelease.version(in: "1401-Mac-2.6.4.24.zip") == "2.6.4.24", "app zip parser accepts downstream build versions")
    check(AppUpdateRelease.version(in: "nullmoth-nvidia-2.6.4.tar.gz") == nil, "driver packages cannot be treated as app updates")

    var progress = NativeTaskState()
    progress.beginAppCheck()
    check(progress.active.count == 1 && progress.active[0].id == "updateCheck", "automatic app-only check uses the existing single progress bar")
    progress.begin(["act": "checkUpdate"])
    progress.receive("appCheck", ["state": "checked"])
    progress.receive("upd", ["state": "checked"])
    check(progress.active.count == 1, "coalesced manual and auto checks retain outstanding app completion")
    progress.receive("appCheck", ["state": "checked"])
    check(progress.active.isEmpty, "all shared check subscribers finish the existing progress bar")
    progress.begin(["act": "updateApp"])
    progress.receive("taskProgress", ["task": "appUpdate", "fraction": 0.95])
    progress.receive("appupd", ["state": "waiting"])
    check(progress.active.first?.fraction == 0.95, "waiting for existing work retains verified progress")
}
