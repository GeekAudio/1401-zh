import Foundation

struct NativeDestination {
    let id: String
    let title: String
    static let all = [
        NativeDestination(id: "drv", title: "本机"),
        NativeDestination(id: "efi", title: "问题"),
        NativeDestination(id: "tools", title: "工具 · 挂载 EFI"),
        NativeDestination(id: "usb", title: "USB 端口"),
        NativeDestination(id: "crash", title: "发送报告"),
    ]
}

struct PageNode: Decodable {
    let kind: String
    let id: String
    let text: String
    let children: [PageNode]
    let key: String

    private enum CodingKeys: String, CodingKey { case kind, id, text, children }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(String.self, forKey: .kind)
        id = try values.decode(String.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        children = try values.decode([PageNode].self, forKey: .children)
        key = decoder.codingPath.map(\.stringValue).joined(separator: "/")
    }

    init(kind: String, id: String, text: String, children: [PageNode]) {
        self.kind = kind
        self.id = id
        self.text = text
        self.children = children
        key = "layout/" + kind + "/" + id
    }
}

struct NativeRecord: Identifiable {
    let key: String
    let value: [String: Any]
    var id: String { key }
}
