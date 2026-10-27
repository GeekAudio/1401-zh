import Foundation
enum Downstream {
    static let repository = "GeekAudio/1401-zh"
    static let appName = "1401 中文版"
    static let source = "https://github.com/" + repository
    static let releases = source + "/releases"
    static let issues = source + "/issues/new"
    static let api = "https://api.github.com/repos/" + repository
    static func packageURL(_ name: String) -> URL { URL(string: releases + "/latest/download/" + name)! }
}
