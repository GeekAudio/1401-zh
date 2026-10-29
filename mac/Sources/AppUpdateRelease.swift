import Foundation

struct AppUpdateRelease {
    let version: String
    let name: String
    let url: URL
    let sha256: String
    let signature: URL

    static func version(in name: String) -> String? {
        let pattern = #"^1401-Mac-([0-9]+\.[0-9]+(?:\.[0-9]+){0,2})\.zip$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[range])
    }
}
