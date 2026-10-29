import Foundation
import CryptoKit
import SwiftUI

var passed = 0
func check(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fatalError("FAILED: " + name) }; passed += 1
}
let model = NativeModel()
var commands: [[String: Any]] = []
model.action = { commands.append($0) }
check(!model.canInstall, "no install before scan")
let scan: [String: Any] = ["arch": "x86_64", "major": 26, "opencore": "REL-110", "gpus": [["supported": true]], "packages": [["ok": "yes", "path": "/tmp/driver.tar.gz"]]]
model.receive("scan", scan)
check(!model.canInstall, "no install before preview")
check(model.disabled("go"), "install button stays disabled before preview")
model.perform("run", ["mode": "dry"])
model.receive("run", ["mode": "dry", "state": "end", "ok": true])
check(model.canInstall, "successful preview enables install")
model.efi = "disk2s1"
check(!model.canInstall, "changing EFI invalidates preview")
model.perform("run", ["mode": "dry"])
model.receive("run", ["mode": "dry", "state": "end", "ok": false])
check(!model.canInstall, "failed preview cannot enable install")
model.perform("run", ["mode": "dry"])
model.receive("run", ["mode": "dry", "state": "end", "ok": true])
var ejected = scan; ejected["packages"] = []
model.receive("scan", ejected)
check(model.package == "/tmp/driver.tar.gz", "scan retains downloaded package like the original interface")
model.receive("scan", scan)
model.perform("run", ["mode": "dry"])
model.efi = "disk3s1"
model.receive("run", ["mode": "dry", "state": "end", "ok": true])
check(model.previewed, "successful preview follows the original completion behavior")
check(UpdateChannel.newer("2.6.2.10", than: "2.6.2.9"), "numeric downstream build ordering")
check(!UpdateChannel.newer("2.6.2.9", than: "2.6.2.10"), "older app not offered")
check(UpdateChannel.pick(["tag_name": "v2.6.2.10", "assets": [], "draft": true], early: true) == nil, "draft release refused")
check(UpdateChannel.pick(["tag_name": "v2.6.2.10", "assets": [], "prerelease": true], early: false) == nil, "prerelease refused for stable channel")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let archive = directory.appendingPathComponent("app.zip")
let bytes = Data("downloaded app bytes".utf8); try bytes.write(to: archive)
let key = Curve25519.Signing.PrivateKey(), other = Curve25519.Signing.PrivateKey()
let sig = try key.signature(for: bytes).base64EncodedString()
check(AppReleaseSignature.verify(zip: archive, signatureBase64: sig, publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()), "valid app update accepted")
check(!AppReleaseSignature.verify(zip: archive, signatureBase64: sig, publicKeyBase64: other.publicKey.rawRepresentation.base64EncodedString()), "foreign signer refused")
check(!AppReleaseSignature.verify(zip: archive, signatureBase64: "", publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()), "missing signature refused")
try Data("tampered app bytes".utf8).write(to: archive)
check(!AppReleaseSignature.verify(zip: archive, signatureBase64: sig, publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()), "tampered update refused")
check(AppReleaseSignature.publicKeyBase64 != ReleaseSignature.publicKeyBase64, "fork app key is separate from upstream test-driver key")
testTaskProgress()
testAutomaticUpdates()
testUpdateClient()
print("Native installation gates, release channel, Ed25519 authenticity and task progress: \(passed) checks passed")
