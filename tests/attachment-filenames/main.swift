import AppKit
import ImageIO
import UniformTypeIdentifiers

struct TestFailure: Error, CustomStringConvertible { let description: String }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(description: message) }
}

let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHATTERBOX_DATA_DIR"]!)
let originals = root.appendingPathComponent("Originals", isDirectory: true)
try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)

func image(_ name: String, type: UTType, width: Int = 32) throws -> URL {
    let url = originals.appendingPathComponent(name)
    let context = CGContext(data: nil, width: width, height: 24, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: 24))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    try check(CGImageDestinationFinalize(destination), "write source image")
    return url
}

#if !BASELINE
func dropped(_ provider: NSItemProvider) throws -> Attachment {
    let lock = NSLock()
    var result: Result<Attachment, Error>?
    let accepted = Attachments.importDrop(provider) { value in
        lock.lock(); result = value; lock.unlock()
    }
    try check(accepted, "drop was rejected")
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        lock.lock(); let value = result; lock.unlock()
        if let value { return try value.get() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    throw TestFailure(description: "provider callback timed out")
}

func promisedFile(_ url: URL, name: String?, type: UTType) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = name
    provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
        completion(url, false, nil)
        return nil
    }
    return provider
}
#endif

do {
    let jpg = try image("Team photo.JPG", type: .jpeg)
    let jpgBytes = try Data(contentsOf: jpg)
    let attachedJPG = try Attachments.importFile(jpg)
    try check(attachedJPG.name == "Team photo.JPG", "JPEG name changed: \(attachedJPG.name)")
    try check(attachedJPG.url.lastPathComponent == attachedJPG.name, "JPEG storage name changed")
    try check(Data(contentsOf: attachedJPG.url) == jpgBytes, "native JPEG bytes changed")

    let png = try image("Proof v1.2.png", type: .png)
    let pngBytes = try Data(contentsOf: png)
    let namedImage = try Attachments.importImageData(pngBytes, name: "Proof v1.2.png")
    try check(namedImage.name == "Proof v1.2.png", "named image extension duplicated: \(namedImage.name)")
    let dottedStem = try Attachments.importImageData(pngBytes, name: "Proof v1.2")
    try check(dottedStem.name == "Proof v1.2.png", "dotted stem lost")
    let pasted = try Attachments.importImageData(pngBytes)
    try check(pasted.name == "Pasted image.png", "unnamed clipboard image regressed")
    let reserved = try Attachments.importImageData(pngBytes, name: "Proof: final.png")
    try check(reserved.name == "Proof: final.png", "display name was sanitized")
    try check(reserved.url.lastPathComponent == "Proof_ final.png", "storage path was not sanitized")

    let tiff = try image("Scan.v3.tif", type: .tiff)
    let tiffBytes = try Data(contentsOf: tiff)
    let converted = try Attachments.importFile(tiff)
    try check(converted.name == "Scan.v3.jpeg", "conversion lost original stem: \(converted.name)")
    try check(converted.mediaType == "image/jpeg", "conversion MIME mismatch")
    try check(CGImageSourceGetType(CGImageSourceCreateWithURL(converted.url as CFURL, nil)!) as String? == UTType.jpeg.identifier,
              "conversion bytes do not match extension")
    let large = try image("Wide proof.jpg", type: .jpeg, width: 3000)
    let resized = try Attachments.importFile(large)
    try check(resized.name == "Wide proof.jpg", "resize changed matching extension")
    let resizedSource = CGImageSourceCreateWithURL(resized.url as CFURL, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(resizedSource, 0, nil)! as NSDictionary
    try check(properties[kCGImagePropertyPixelWidth] as? Int == Attachments.maxImageEdge, "resizing regressed")

    #if !BASELINE
    let finder = try dropped(NSItemProvider(object: jpg as NSURL))
    try check(finder.name == "Team photo.JPG", "Finder drop changed name: \(finder.name)")
    let pdf = originals.appendingPathComponent("Magazine proof.pdf")
    let pdfBytes = Data("%PDF-1.7 filename fixture".utf8)
    try pdfBytes.write(to: pdf)
    let promised = try dropped(promisedFile(pdf, name: "Magazine proof.pdf", type: .pdf))
    try check(promised.name == "Magazine proof.pdf", "promised file extension duplicated: \(promised.name)")
    let illustrator = originals.appendingPathComponent("Ribbon artwork.ai")
    let artworkBytes = Data("%!PS-Adobe-3.0 Illustrator source fixture".utf8)
    try artworkBytes.write(to: illustrator)
    let artwork = try dropped(promisedFile(illustrator, name: "Ribbon artwork.ai",
                                          type: UTType(filenameExtension: "ai")!))
    try check(artwork.name == "Ribbon artwork.ai" && artwork.kind != .image,
              "design file was renamed or flattened")
    try check(Data(contentsOf: artwork.url) == artworkBytes, "design source bytes changed")
    let extensionless = try dropped(promisedFile(pdf, name: "Magazine proof", type: .pdf))
    try check(extensionless.name == "Magazine proof.pdf", "missing extension was not added")
    let fallback = try dropped(promisedFile(pdf, name: nil, type: .pdf))
    try check(fallback.name == "Magazine proof.pdf", "representation filename lost: \(fallback.name)")
    let rawImage = NSItemProvider()
    rawImage.suggestedName = "Screenshot final.png"
    rawImage.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
        completion(pngBytes, nil)
        return nil
    }
    let droppedImage = try dropped(rawImage)
    try check(droppedImage.name == "Screenshot final.png", "image-data drop changed name: \(droppedImage.name)")
    try check(Data(contentsOf: droppedImage.url) == pngBytes, "image-data drop changed bytes")
    try FileManager.default.removeItem(at: pdf)
    try check(Data(contentsOf: promised.url) == pdfBytes, "promised copy expired with provider URL")
    let restored = try JSONDecoder().decode(Attachment.self, from: JSONEncoder().encode(droppedImage))
    try check(restored.name == "Screenshot final.png", "saved message lost filename")
    print("Finder: \(finder.name); promised: \(promised.name); design: \(artwork.name); image data: \(droppedImage.name)")
    #endif

    try check(Data(contentsOf: jpg) == jpgBytes && Data(contentsOf: png) == pngBytes
              && Data(contentsOf: tiff) == tiffBytes, "original files changed")
    print("PASS: original filenames survive URL, promised-file and image-data drops; extensions, conversion, storage safety and source bytes verified.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
