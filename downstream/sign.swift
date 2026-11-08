import Foundation
import CryptoKit
import Darwin
let args = CommandLine.arguments

/// What the fork's release key signs: the same message 1401 2.7.2 introduced upstream, so a signed archive cannot
/// stand in for another product and an old signed archive cannot replace a newer one.
func boundMessage(product: String, version: String, sha256: String) -> Data {
    Data("nullmoth-release-v1\n\(product)\n\(version)\n\(sha256)\n".utf8)
}

if args.count == 3 && args[1] == "generate" {
    let key = Curve25519.Signing.PrivateKey()
    let data = try JSONSerialization.data(withJSONObject: ["private": key.rawRepresentation.base64EncodedString(), "public": key.publicKey.rawRepresentation.base64EncodedString()])
    let url = URL(fileURLWithPath: args[2])
    guard !FileManager.default.fileExists(atPath: url.path) else { fatalError("Refusing to overwrite an existing key") }
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else if args.count == 4 && args[1] == "sign" {
    guard let seed = ProcessInfo.processInfo.environment["RELEASE_SIGNING_KEY"], let data = Data(base64Encoded: seed) else { fatalError("Missing release key") }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    let zip = URL(fileURLWithPath: args[2]), version = args[3]
    let bytes = try Data(contentsOf: zip)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    // .bsig: product, version and SHA-256 bound together. This is what 1401 中文版 2.8 and later read.
    let bound = try key.signature(for: boundMessage(product: "1401-mac", version: version, sha256: digest))
    try bound.base64EncodedString().write(to: URL(fileURLWithPath: zip.path + ".bsig"), atomically: true, encoding: .utf8)
    guard key.publicKey.isValidSignature(bound, for: boundMessage(product: "1401-mac", version: version, sha256: digest)) else { fatalError("Bound signature self-check failed") }
    // .sig: the bare archive signature, kept so an app older than 2.8.62 can still verify and update itself once.
    let legacy = try key.signature(for: bytes)
    try legacy.base64EncodedString().write(to: URL(fileURLWithPath: zip.path + ".sig"), atomically: true, encoding: .utf8)
    guard key.publicKey.isValidSignature(legacy, for: bytes) else { fatalError("Signature self-check failed") }
    print("Detached Ed25519 signatures verified (.bsig bound to 1401-mac \(version), .sig for older apps)")
} else { fatalError("Usage: sign.swift generate key-file | sign archive.zip version") }
