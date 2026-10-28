import AppKit

final class ChineseAlert: NSAlert {
    override func runModal() -> NSApplication.ModalResponse {
        messageText = ZH.text(messageText)
        informativeText = ZH.text(informativeText)
        for button in buttons { button.title = ZH.text(button.title) }
        return super.runModal()
    }
}
final class ChineseOpenPanel: NSOpenPanel {
    override func runModal() -> NSApplication.ModalResponse {
        title = ZH.text(title)
        prompt = ZH.text(prompt)
        message = ZH.text(message)
        return super.runModal()
    }
}
