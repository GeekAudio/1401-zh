import AppKit

final class ChineseAlert: NSAlert {
    private func localize() {
        messageText = ZH.text(messageText)
        informativeText = ZH.text(informativeText)
        for button in buttons { button.title = ZH.text(button.title) }
    }

    override func runModal() -> NSApplication.ModalResponse {
        localize()
        return super.runModal()
    }

    override func beginSheetModal(
        for sheetWindow: NSWindow,
        completionHandler handler: ((NSApplication.ModalResponse) -> Void)?
    ) {
        localize()
        super.beginSheetModal(for: sheetWindow, completionHandler: handler)
    }
}

final class ChineseOpenPanel: NSOpenPanel {
    private func localize() {
        title = ZH.text(title)
        prompt = ZH.text(prompt)
        message = ZH.text(message)
    }

    override func runModal() -> NSApplication.ModalResponse {
        localize()
        return super.runModal()
    }

    override func beginSheetModal(
        for window: NSWindow,
        completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        localize()
        super.beginSheetModal(for: window, completionHandler: handler)
    }
}
