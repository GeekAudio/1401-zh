import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: folder) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale, n = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: n, height: n))
        image.lockFocus()
        NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.07, y: n * 0.07, width: n * 0.86, height: n * 0.86), xRadius: n * 0.2, yRadius: n * 0.2).fill()
        let cfg = NSImage.SymbolConfiguration(pointSize: n * 0.52, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let white = NSImage(size: symbol.size); white.lockFocus(); NSColor.white.set(); symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1); NSColor.white.set(); NSRect(origin: .zero, size: symbol.size).fill(using: .sourceIn); white.unlockFocus()
            white.draw(in: NSRect(x: n * 0.24, y: n * 0.24, width: n * 0.52, height: n * 0.52))
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", folder.path, "-o", output.path]
try p.run(); p.waitUntilExit(); exit(p.terminationStatus)
