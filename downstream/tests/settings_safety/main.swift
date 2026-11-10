import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAILED: " + message) }
    print("ok   " + message)
}
let catalogURL = URL(fileURLWithPath: CommandLine.arguments[1])
let catalog = DriverSettings.load(try Data(contentsOf: catalogURL))!
let hdr = catalog.find("hdr")!
let fps = catalog.find("fps-limit")!
check(NativeSettingsSafety.parseBootArgs("boot-args\t-v keepsyms=1\n", status: 0) == "-v keepsyms=1", "read existing boot args")
check(NativeSettingsSafety.parseBootArgs("boot-args\t-v\n", status: 1) == nil, "failed nvram command is not empty boot args")
check(NativeSettingsSafety.parseBootArgs("unexpected\t-v\n", status: 0) == nil, "unexpected nvram output is refused")
check((try? NativeSettingsSafety.plan(catalog, hdr, "on", bootArgs: nil, conf: "")) == nil, "unreadable boot args cannot produce a write")
check((try? NativeSettingsSafety.plan(catalog, fps, "60", bootArgs: "", conf: nil)) == nil, "unreadable config cannot produce a write")
let bootPlan = try NativeSettingsSafety.plan(catalog, hdr, "on", bootArgs: "-v keepsyms=1", conf: nil)
if case let .bootArgs(line) = bootPlan { check(line.contains("-v") && line.contains("keepsyms=1"), "boot plan preserves existing arguments") }
else { fatalError("FAILED: expected boot-args plan") }
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: dir) }
let file = dir.appendingPathComponent("nvrm610.conf")
check(NativeSettingsSafety.readConfiguration(file.path) == "", "genuinely absent config in readable directory uses default")
try Data([0xff, 0xfe]).write(to: file)
check(NativeSettingsSafety.readConfiguration(file.path) == nil, "unreadable non-UTF8 config cannot be overwritten")
try FileManager.default.removeItem(at: file)
try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: "missing-target")
check(NativeSettingsSafety.readConfiguration(file.path) == nil, "broken configuration symlink is not treated as absent")
try FileManager.default.removeItem(at: file)
let realFile = dir.appendingPathComponent("real.conf")
try "existing=true\n".write(to: realFile, atomically: true, encoding: .utf8)
try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: realFile.path)
check(NativeSettingsSafety.readConfiguration(file.path) == nil, "configuration symlink cannot be replaced by an atomic write")
let absentParent = dir.appendingPathComponent("missing").appendingPathComponent("nvrm610.conf")
check(NativeSettingsSafety.readConfiguration(absentParent.path) == nil, "missing parent is not treated as empty configuration")
print("Native settings read safety checks passed")
