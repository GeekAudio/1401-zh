import Foundation

enum L10n {
    enum Language: String, CaseIterable {
        case english = "en"
        case simplifiedChinese = "zh-Hans"
        case traditionalChinese = "zh-Hant"

        static func preferred(for preferences: [String]) -> Self {
            let candidates = allCases.map(\.rawValue)
            let match = Bundle.preferredLocalizations(from: candidates, forPreferences: preferences).first
            return match.flatMap(Self.init(rawValue:)) ?? .english
        }
    }

    static let language: Language = {
        if !Bundle.main.localizations.isEmpty,
           let preferred = Bundle.main.preferredLocalizations.first,
           let supported = Language(rawValue: preferred) {
            return supported
        }
        // Command-line test targets have no bundle localization declarations.
        return Language.preferred(for: Locale.preferredLanguages)
    }()

    static var isChinese: Bool { language != .english }
    static let pageTextKey = CodingUserInfoKey(rawValue: "native-page-text")!
    private static let traditional = StringTransform("Simplified-Traditional")

    // Convert UI copy in Traditional Chinese while retaining values such as names and paths.
    struct ChineseText: ExpressibleByStringInterpolation {
        let value: String

        init(stringLiteral value: String) { self.value = L10n.chinese(value) }
        init(stringInterpolation: StringInterpolation) { value = stringInterpolation.value }

        struct StringInterpolation: StringInterpolationProtocol {
            private(set) var value = ""

            init(literalCapacity: Int, interpolationCount: Int) {
                value.reserveCapacity(literalCapacity)
            }

            mutating func appendLiteral(_ text: String) { value += L10n.chinese(text) }
            mutating func appendInterpolation<T>(_ value: T) { self.value += String(describing: value) }
        }
    }

    static func ui(_ chinese: ChineseText, _ english: @autoclosure () -> String) -> String {
        isChinese ? chinese.value : english()
    }

    static func ui(chinese: String, english: @autoclosure () -> String) -> String {
        isChinese ? self.chinese(chinese) : english()
    }

    static func chinese(_ text: String) -> String {
        guard language == .traditionalChinese else { return text }
        return text.applyingTransform(traditional, reverse: false) ?? text
    }

    static func pageDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let english = pageText(for: .english)
        let localized = isChinese ? pageText(for: .simplifiedChinese).mapValues(chinese) : [:]
        decoder.userInfo[pageTextKey] = english.merging(localized) { _, translated in translated }
        return decoder
    }

    private static func pageText(for language: Language) -> [String: String] {
        guard let url = Bundle.main.url(forResource: "native-page-text", withExtension: "json",
                                       subdirectory: nil, localization: language.rawValue),
              let data = try? Data(contentsOf: url),
              let text = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return text
    }
}

enum ZH {
    static let entries: [String: String] = {
        guard let url = Bundle.main.url(forResource: "zh-Hans", withExtension: "json"),
              let data = try? Data(contentsOf: url), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return dict
    }()
    static func text(_ value: String) -> String {
        guard L10n.isChinese else { return value }
        if let translated = entries[value] { return L10n.chinese(translated) }
        if value.contains("\n") { return value.components(separatedBy: "\n").map(text).joined(separator: "\n") }
        for key in entries.keys.sorted(by: { $0.count > $1.count }) where key.contains("%@") {
            let parts = key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:))
            guard let regex = try? NSRegularExpression(pattern: "^" + parts.joined(separator: "(.+?)") + "$"),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            var result = L10n.chinese(entries[key]!)
            for i in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: i), in: value), let placeholder = result.range(of: "%@") { result.replaceSubrange(placeholder, with: value[range]) }
            }
            return result
        }
        return value
    }
}
