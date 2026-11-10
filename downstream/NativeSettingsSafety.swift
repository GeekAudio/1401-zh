import Foundation
import Darwin

// Distinguish absent configuration from an unreadable file before building a privileged command.
enum NativeSettingsSafety {
    enum ReadError: LocalizedError {
        case bootArgs, configuration
        var errorDescription: String? {
            switch self {
            case .bootArgs: return "无法读取当前启动参数，未更改设置。"
            case .configuration: return "无法读取现有驱动配置，未更改设置。"
            }
        }
    }
    static func parseBootArgs(_ output: String, status: Int32) -> String? {
        guard status == 0, let tab = output.firstIndex(of: "\t"), output[..<tab] == "boot-args" else { return nil }
        return output[output.index(after: tab)...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func readConfiguration(_ path: String) -> String? {
        var info = stat()
        if lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK { return nil }
        do { return try String(contentsOfFile: path, encoding: .utf8) }
        catch {
            // An absent file is the legitimate initial default; never treat a broken link,
            // permission error, or unreadable parent as an empty existing configuration.
            let missing = lstat(path, &info) == -1 && errno == ENOENT
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            return missing && FileManager.default.isReadableFile(atPath: parent) ? "" : nil
        }
    }
    static func plan(_ catalog: DriverSettings.Catalog, _ setting: DriverSettings.Setting, _ value: String,
                     bootArgs: String?, conf: String?) throws -> DriverSettings.Change {
        if setting.where_ == "bootarg" && bootArgs == nil { throw ReadError.bootArgs }
        if setting.where_ != "bootarg" && conf == nil { throw ReadError.configuration }
        return try DriverSettings.plan(catalog, setting, value, bootArgs: bootArgs ?? "", conf: conf ?? "")
    }
}
