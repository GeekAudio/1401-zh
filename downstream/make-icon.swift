import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceURL = URL(fileURLWithPath: #filePath)
    .standardizedFileURL.deletingLastPathComponent()
    .appendingPathComponent("assets/1401-icon.png")
let sourceData = try Data(contentsOf: sourceURL)
guard let source = NSImage(data: sourceData) else {
    fatalError("Cannot read icon source at \(sourceURL.path)")
}
guard let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot decode icon source at \(sourceURL.path)")
}
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: folder) }

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let destination = folder.appendingPathComponent(name)
        if pixels == 512 {
            try sourceData.write(to: destination)
            continue
        }
        let context = CGContext(data: nil, width: pixels, height: pixels,
                                bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", folder.path, "-o", output.path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
