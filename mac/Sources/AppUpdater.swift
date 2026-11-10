// App-only update checks and scheduling; driver channels remain upstream.
import AppKit

extension App {
    func checkForkAppUpdate(completion: ((String?) -> Void)? = nil) {
        appUpdateClient.check { result in
            switch result {
            case .success(let release):
                self.latestApp = (release.version, release.name, release.url, release.sha256, release.signature)
                let newer = App.newer(release.version, than: self.appVersion)
                self.send("appCheck", ["state": "checked", "latest": release.version, "have": self.appVersion, "newer": newer])
                self.automaticAppUpdates.offer(newer ? release.version : nil)
                completion?(newer ? release.version : nil)
            case .failure(let error):
                self.send("appCheck", ["state": "error", "why": error.localizedDescription])
                completion?(nil)
            }
        }
    }

    func startAutomaticAppUpdates() {
        automaticAppUpdates.start(version: appVersion, check: { [weak self] completion in
            guard let self else { return completion(nil) }
            self.native.tasks.beginAppCheck()
            self.checkForkAppUpdate(completion: completion)
        }, isIdle: { [weak self] in self?.canRestartForAppUpdate == true }, install: { [weak self] in
            self?.perform(["act": "updateApp"])
        })
    }

    private var canRestartForAppUpdate: Bool {
        let settings = SettingsPanel.shared
        return AppUpdateIdleState(
            setupRunning: runningSetup,
            downloadPending: pendingDownload != nil,
            usbWatching: usbTimer != nil,
            nativeBusy: native.busy,
            downloading: native.downloading,
            driverUpdating: native.driverUpdating,
            collecting: native.collecting,
            mappingGPU: native.mappingGPU,
            checkingEFI: native.checkingEFI,
            mountingEFI: native.mountingEFI,
            tccGranting: native.tccGranting,
            gameModeBusy: native.gameModeBusy,
            settingsPanelOpen: settings != nil,
            settingsBusy: settings?.busy == true,
            activeTaskIDs: native.tasks.active.map(\.id),
            modalWindowOpen: NSApp.modalWindow != nil,
            attachedSheetOpen: window.attachedSheet != nil
        ).canReplaceApp
    }

    func appUpdateFailed(_ reason: String) {
        DispatchQueue.main.async {
            self.automaticAppUpdates.failed()
            self.send("appupd", ["state": "error", "why": reason])
        }
    }

    func replaceAppWhenIdle(version: String, _ action: @escaping () -> Void) {
        DispatchQueue.main.async {
            if !self.canRestartForAppUpdate { self.send("appupd", ["state": "waiting", "version": version]) }
            self.automaticAppUpdates.replaceWhenIdle(action)
        }
    }
}
