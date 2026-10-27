import Foundation
import CryptoKit
import Darwin
let args = CommandLine.arguments
if args.count == 3 && args[1] == "generate" {
    let key = Curve25519.Signing.PrivateKey()
    let data = try JSONSerialization.data(withJSONObject: ["private": key.rawRepresentation.base64EncodedString(), "public": key.publicKey.rawRepresentation.base64EncodedString()])
    let url = URL(fileURLWithPath: args[2])
    guard !FileManager.default.fileExists(atPath: url.path) else { fatalError("Refusing to overwrite an existing key") }
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else if args.count == 3 && args[1] == "sign" {
    guard let seed = ProcessInfo.processInfo.environment["RELEASE_SIGNING_KEY"], let data = Data(base64Encoded: seed) else { fatalError("Missing release key") }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    let zip = URL(fileURLWithPath: args[2]), bytes = try Data(contentsOf: zip)
    let signature = try key.signature(for: bytes)
    try signature.base64EncodedString().write(to: URL(fileURLWithPath: zip.path + ".sig"), atomically: true, encoding: .utf8)
    guard key.publicKey.isValidSignature(signature, for: bytes) else { fatalError("Signature self-check failed") }
    print("Detached Ed25519 signature verified")
} else { fatalError("Usage: sign.swift generate key-file | sign archive.zip") }
