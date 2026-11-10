import Foundation

struct NativeDestination: Identifiable {
    let id: String
    let title: String
    let symbol: String
    static let all = [
        NativeDestination(id: "drv", title: "本机", symbol: "desktopcomputer"),
        NativeDestination(id: "efi", title: "问题", symbol: "exclamationmark.triangle"),
        NativeDestination(id: "tools", title: "工具", symbol: "wrench.and.screwdriver"),
        NativeDestination(id: "experimental", title: "实验", symbol: "flask"),
        NativeDestination(id: "usb", title: "USB", symbol: "cable.connector"),
        NativeDestination(id: "crash", title: "报告", symbol: "paperplane"),
    ]
}

struct PageNode: Decodable {
    let kind: String
    let id: String
    let text: String
    let value: String
    let children: [PageNode]
    let key: String

    private enum CodingKeys: String, CodingKey { case kind, id, text, value, children }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(String.self, forKey: .kind)
        id = try values.decode(String.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        value = try values.decodeIfPresent(String.self, forKey: .value) ?? ""
        children = try values.decode([PageNode].self, forKey: .children)
        key = decoder.codingPath.map(\.stringValue).joined(separator: "/")
    }

    init(kind: String, id: String, text: String, children: [PageNode]) {
        self.kind = kind
        self.id = id
        self.text = text
        value = ""
        self.children = children
        key = "layout/" + kind + "/" + id
    }

    func contains(id: String) -> Bool {
        self.id == id || children.contains { $0.contains(id: id) }
    }
}

// Rearrange the original nodes for native navigation without changing their actions or copy.
enum NativePageLayout {
    static func pages(from source: [PageNode]) -> [PageNode] {
        guard let tools = source.first(where: { $0.id == "tools" }) else { return source }

        var system: [PageNode] = []
        var display: [PageNode] = []
        var apps: [PageNode] = []
        var switches: [PageNode] = []
        var testDrivers: [PageNode] = []
        var storageHelp: [PageNode] = []
        var measurements: [PageNode] = []
        for card in tools.children where card.kind != "title" {
            if card.id == "exppane" { switches.append(card) }
            else if card.id == "xecard" || card.contains(id: "gpuon") { testDrivers.append(card) }
            else if card.id == "vmdpane" { storageHelp.append(card) }
            else if card.contains(id: "gpumap") { measurements.append(card) }
            else if card.id == "armcard" || card.contains(id: "tccg") { apps.append(card) }
            else if ["blon", "hdon", "hybcopy", "boston", "ryzon", "gmon", "settings"].contains(where: { card.contains(id: $0) }) {
                display.append(card)
            } else { system.append(card) }
        }

        // Prioritize the settings panel, then keep the upstream order of the remaining cards.
        if let index = display.firstIndex(where: { $0.contains(id: "settings") }) {
            let settings = display.remove(at: index)
            display.insert(settings, at: 0)
        }

        return source.flatMap { page -> [PageNode] in
            switch page.id {
            case "tools":
                let toolsPage = PageNode(kind: "page", id: page.id, text: "", children:
                    page.children.filter { $0.kind == "title" } + [
                        category("system", "系统与启动", system),
                        category("display", "显示与性能", display),
                        category("apps", "应用与权限", apps),
                    ])
                let experiment = PageNode(kind: "page", id: "experimental", text: "", children: [
                    PageNode(kind: "title", id: "experimental-title", text: "实验", children: []),
                    category("switches", "功能开关", switches),
                    category("test-drivers", "测试驱动", testDrivers),
                ])
                return [toolsPage, experiment]
            case "efi":
                return [PageNode(kind: "page", id: page.id, text: "", children: page.children + storageHelp)]
            case "crash":
                let footer = page.children.firstIndex(where: { $0.kind == "legal" }) ?? page.children.endIndex
                let children = Array(page.children[..<footer]) + measurements + Array(page.children[footer...])
                return [PageNode(kind: "page", id: page.id, text: "", children: children)]
            default: return [page]
            }
        }
    }

    private static func category(_ id: String, _ title: String, _ cards: [PageNode]) -> PageNode {
        PageNode(kind: "category", id: id, text: title, children: cards)
    }
}

struct NativeRecord: Identifiable {
    let key: String
    let value: [String: Any]
    var id: String { key }
}
