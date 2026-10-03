import AppKit
import CoreImage

let size = 1024.0
func load(_ name: String) -> CIImage { CIImage(contentsOf: URL(fileURLWithPath: name))! }
func scaled(_ image: CIImage, toWidth width: Double) -> CIImage {
    let s = width / image.extent.width
    let f = CIFilter(name: "CILanczosScaleTransform")!
    f.setValue(image, forKey: kCIInputImageKey); f.setValue(s, forKey: kCIInputScaleKey); f.setValue(1.0, forKey: kCIInputAspectRatioKey)
    return f.outputImage!
}
let ctx = CIContext()
func cg(_ i: CIImage) -> CGImage { ctx.createCGImage(i, from: i.extent)! }

let variant = CommandLine.arguments[1]
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
c.interpolationQuality = .high
let dark = variant == "dark" || variant == "tinted"
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let (top, bottom, glow) = dark
    ? (rgb(0.17, 0.18, 0.20), rgb(0.07, 0.075, 0.085), rgb(0.40, 0.36, 0.31, 0.55))
    : (rgb(0.97, 0.95, 0.91), rgb(0.87, 0.84, 0.78), rgb(1, 1, 1, 0.75))
// Background: a vertical wash, and a soft glow behind him.
c.drawLinearGradient(CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!,
                     start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
c.drawRadialGradient(CGGradient(colorsSpace: space, colors: [glow, glow.copy(alpha: 0)!] as CFArray, locations: [0, 1])!,
                     startCenter: CGPoint(x: 512, y: 560), startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 540, options: [])

let head = load("head.png"), chest = load("stone-chest.png")
let headW = Double(CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 830), chestW = headW * 0.63
let headImg = cg(scaled(head, toWidth: headW)), chestImg = cg(scaled(chest, toWidth: chestW))
let headH = headW * head.extent.height / head.extent.width
let chestH = chestW * chest.extent.height / chest.extent.width
// The chest peeks up from the bottom edge; the head rests on it.
let chestRect = CGRect(x: (size - chestW) / 2, y: chestH * 0.38, width: chestW, height: chestH)
let headRect = CGRect(x: (size - headW) / 2, y: chestRect.maxY - headH * 0.09, width: headW, height: headH)
c.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0, 0, 0, dark ? 0.55 : 0.28))
c.draw(chestImg, in: chestRect)
c.draw(headImg, in: headRect)
var final = c.makeImage()!
if variant == "tinted" {
    let gray = CIImage(cgImage: final).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.1])
    final = ctx.createCGImage(gray, from: gray.extent)!
}
let out = NSBitmapImageRep(cgImage: final)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "golem-icon-\(variant).png"))
print("wrote golem-icon-\(variant).png")
