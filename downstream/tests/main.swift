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
func semanticParts(_ text: String) -> [String] {
    NativePageView.semanticParagraphs(text).flatMap { $0.flatMap { $0 } }
}
let markedCopy = "版本 2.6.6.54 已安装。请保持 U 盘连接，否则将无法启动。查看 [升级说明](https://example.com/releases/v2.6.6.54?source=macOS) 后再操作。**重要提示。**不要关闭电脑。"
let markedParagraphs = NativePageView.semanticParagraphs(markedCopy)
let markedSegments = semanticParts(markedCopy)
check(markedParagraphs[0][0].joined().hasSuffix("已安装。"), "sentence boundary follows its original full stop")
check(markedSegments.joined() == markedCopy, "visual layout fragments preserve exact source copy")
check(markedSegments.contains(where: { $0.contains("2.6.6.54") }), "version numbers remain whole across fragments")
check(markedSegments.contains(where: { $0.contains("[升级说明](https://example.com/releases/v2.6.6.54?source=macOS)") }), "Markdown link and URL remain whole")
check(markedSegments.contains(where: { $0.contains("**重要提示。**") }), "bold punctuation remains inside its emphasized phrase")
check(SemanticFlowLayout.rowGroups(for: [260, 220, 200], availableWidth: 744) == [[0, 1, 2]],
      "complete sentences share a row when measured widths fit")
check(SemanticFlowLayout.rowGroups(for: [260, 220, 200], availableWidth: 520) == [[0, 1], [2]],
      "sentence moves to the next row when current width is insufficient")
check(SemanticFlowLayout.rowGroups(for: [820, 180], availableWidth: 744) == [[0], [1]],
      "an overwide sentence gets its own wrapped row")
let liveDeviceText = "NullMoth 驱动正在运行（NVIDIA GeForce RTX 3080 (NVMTL over NVIDIA GeForce RTX 3080 (NVK GA102-A))）。已加载 4 个组件，NVIDIA Metal 设备可见。"
let deviceSegments = semanticParts(liveDeviceText)
check(deviceSegments.joined() == liveDeviceText, "dynamic hardware text remains complete")
check(deviceSegments.first?.contains("GA102-A") == true, "dynamic GPU identifiers do not split at ASCII punctuation")
let shortCopy = "设备已就绪。请继续。"
check(semanticParts(shortCopy).joined() == shortCopy, "short copy remains unchanged")
let earlyUpdateCopy = "新驱动会先推送给启用此选项的用户，确认其电脑未出现退步后再向所有人提供。启用后可提前一两天获取版本，\n遇到问题时请发送日志。"
let earlyUpdateParagraphs = NativePageView.semanticParagraphs(earlyUpdateCopy)
check(earlyUpdateParagraphs.count == 2, "early-update copy has exactly two explicit visual lines")
check(earlyUpdateParagraphs[0].flatMap { $0 }.joined().hasSuffix("获取版本，"), "first two sentences stay on line one")
check(earlyUpdateParagraphs[1].flatMap { $0 }.joined() == "遇到问题时请发送日志。", "send-logs instruction starts line two")
check(earlyUpdateParagraphs.map { $0.flatMap { $0 }.joined() }.joined(separator: "\n") == earlyUpdateCopy,
      "early-update line break preserves the original text and punctuation")
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
// 2.7.2 binds the signature to the product, the version and the SHA-256; the fork signs the same message.
let forkKey = key.publicKey.rawRepresentation.base64EncodedString()
let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
let boundMessage = AppReleaseSignature.boundMessage(product: "1401-mac", version: "2.8.62", sha256: digest)
let bound = try key.signature(for: boundMessage).base64EncodedString()
check(AppReleaseSignature.verifyBound(data: bytes, product: "1401-mac", version: "2.8.62", signatureBase64: bound, publicKeyBase64: forkKey), "bound app signature accepted")
check(!AppReleaseSignature.verifyBound(data: bytes, product: "1401-mac", version: "2.8.61", signatureBase64: bound, publicKeyBase64: forkKey), "signature bound to another version refused")
check(!AppReleaseSignature.verifyBound(data: bytes, product: "nullmoth-nvidia", version: "2.8.62", signatureBase64: bound, publicKeyBase64: forkKey), "signature bound to another product refused")
check(AppReleaseSignature.isDowngrade("2.8.61", installed: "2.8.62") && !AppReleaseSignature.isDowngrade("2.8.63", installed: "2.8.62"), "an older signed app cannot replace a newer one")
try Data("tampered app bytes".utf8).write(to: archive)
check(!AppReleaseSignature.verify(zip: archive, signatureBase64: sig, publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()), "tampered update refused")
check(AppReleaseSignature.publicKeyBase64 != ReleaseSignature.publicKeyBase64, "fork app key is separate from upstream test-driver key")
testTaskProgress()
testAutomaticUpdates()
testUpdateClient()
print("Native installation gates, release channel, Ed25519 authenticity and task progress: \(passed) checks passed")
