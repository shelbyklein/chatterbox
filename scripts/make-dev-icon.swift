// Makes Chatterbox Dev's app icons from the real ones: the same icon with an orange "DEV" band
// across its lower part, kept inside the icon's own shape.
//   swift scripts/make-dev-icon.swift
// Writes AppIconDev.appiconset beside each AppIcon.appiconset (Mac and iPhone).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let catalogs = ["Chatterbox/Assets.xcassets", "ChatterboxMobile/Assets.xcassets"]
let orange = NSColor(srgbRed: 0.96, green: 0.45, blue: 0.08, alpha: 1)

func devIcon(_ source: CGImage) -> CGImage {
    let w = source.width, h = source.height
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func context() -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    // The band and its label, then cut to the icon's shape.
    let band = context()
    let bandRect = CGRect(x: 0, y: CGFloat(h) * 0.12, width: CGFloat(w), height: CGFloat(h) * 0.24)
    band.setFillColor(orange.cgColor)
    band.fill(bandRect)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: band, flipped: false)
    let font = NSFont.systemFont(ofSize: bandRect.height * 0.72, weight: .heavy)
    let label = NSAttributedString(string: "DEV", attributes: [.font: font, .foregroundColor: NSColor.white, .kern: bandRect.height * 0.08])
    let size = label.size()
    label.draw(at: CGPoint(x: (CGFloat(w) - size.width) / 2, y: bandRect.midY - size.height / 2 - font.descender / 2))
    NSGraphicsContext.restoreGraphicsState()
    band.setBlendMode(.destinationIn)
    band.draw(source, in: rect)
    // The icon, with the band over it.
    let out = context()
    out.draw(source, in: rect)
    out.draw(band.makeImage()!, in: rect)
    return out.makeImage()!
}

for catalog in catalogs {
    let from = root.appendingPathComponent(catalog).appendingPathComponent("AppIcon.appiconset")
    let to = root.appendingPathComponent(catalog).appendingPathComponent("AppIconDev.appiconset")
    try? FileManager.default.removeItem(at: to)
    try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: from.appendingPathComponent("Contents.json"), to: to.appendingPathComponent("Contents.json"))
    for file in try FileManager.default.contentsOfDirectory(atPath: from.path) where file.hasSuffix(".png") {
        guard let data = try? Data(contentsOf: from.appendingPathComponent(file)),
              let image = NSBitmapImageRep(data: data)?.cgImage else { fatalError("Can't read \(file)") }
        let rep = NSBitmapImageRep(cgImage: devIcon(image))
        try rep.representation(using: .png, properties: [:])!.write(to: to.appendingPathComponent(file))
    }
    print("Wrote \(to.path)")
}
