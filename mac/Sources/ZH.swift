import Foundation

enum ZH {
    static let entries: [String: String] = {
        guard let url = Bundle.main.url(forResource: "zh-Hans", withExtension: "json"),
              let data = try? Data(contentsOf: url), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return dict
    }()
    static func text(_ value: String) -> String {
        if let translated = entries[value] { return translated }
        if value.contains("\n") { return value.components(separatedBy: "\n").map(text).joined(separator: "\n") }
        for key in entries.keys.sorted(by: { $0.count > $1.count }) where key.contains("%@") {
            let parts = key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:))
            guard let regex = try? NSRegularExpression(pattern: "^" + parts.joined(separator: "(.+?)") + "$"),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            var result = entries[key]!
            for i in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: i), in: value), let placeholder = result.range(of: "%@") { result.replaceSubrange(placeholder, with: value[range]) }
            }
            return result
        }
        return value
    }
}
