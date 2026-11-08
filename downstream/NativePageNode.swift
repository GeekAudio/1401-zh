import Foundation

struct NativeDestination: Identifiable {
    let id: String
    let title: String
    let symbol: String
    static let all = [
        NativeDestination(id: "drv", title: "本机", symbol: "desktopcomputer"),
        NativeDestination(id: "efi", title: "问题", symbol: "exclamationmark.triangle"),
        NativeDestination(id: "tools", title: "工具", symbol: "wrench.and.screwdriver"),
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
        // Only a <select>'s <option> carries a value; every other node leaves it empty.
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
}

struct NativeRecord: Identifiable {
    let key: String
    let value: [String: Any]
    var id: String { key }
}
