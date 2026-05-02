import AppKit
import CoreImage

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDir = root.appendingPathComponent("src/Assets.xcassets/AppIcon.appiconset")
let designDir = root.appendingPathComponent("design/app-icons")
let sourceURL = designDir.appendingPathComponent("source-old-icon.png")

try FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: designDir, withIntermediateDirectories: true)

guard let sourceImage = CIImage(contentsOf: sourceURL) else {
    fatalError("Missing source icon: \(sourceURL.path)")
}

let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])

func centeredSquare(_ image: CIImage) -> CIImage {
    let extent = image.extent
    let side = max(extent.width, extent.height)
    let canvas = CGRect(
        x: 0,
        y: 0,
        width: side,
        height: side
    )
    let background = CIImage(color: CIColor(red: 0.66, green: 0.71, blue: 0.73, alpha: 1)).cropped(to: canvas)
    let centered = image.transformed(by: CGAffineTransform(
        translationX: (side - extent.width) / 2 - extent.minX,
        y: (side - extent.height) / 2 - extent.minY
    ))
    return centered.composited(over: background).cropped(to: canvas)
}

func applyFilter(_ image: CIImage, saturation: Double = 1, brightness: Double = 0, contrast: Double = 1) -> CIImage {
    guard let controls = CIFilter(name: "CIColorControls") else { return image }
    controls.setValue(image, forKey: kCIInputImageKey)
    controls.setValue(saturation, forKey: kCIInputSaturationKey)
    controls.setValue(brightness, forKey: kCIInputBrightnessKey)
    controls.setValue(contrast, forKey: kCIInputContrastKey)
    return controls.outputImage ?? image
}

func scaledImage(_ image: CIImage, pixels: Int) -> NSImage {
    let scale = CGFloat(pixels) / image.extent.width
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let cg = context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: pixels, height: pixels)) else {
        fatalError("Could not render \(pixels)x\(pixels)")
    }
    return NSImage(cgImage: cg, size: NSSize(width: pixels, height: pixels))
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let data = rep.representation(using: .png, properties: [:])
    else {
        fatalError("Could not encode \(url.lastPathComponent)")
    }
    try data.write(to: url)
}

func drawPreviewSheet(_ variants: [(name: String, image: CIImage)]) throws {
    let tile: CGFloat = 360
    let margin: CGFloat = 64
    let labelHeight: CGFloat = 70
    let width = margin * 2 + tile * CGFloat(variants.count)
    let height = margin * 2 + tile + labelHeight
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width),
        pixelsHigh: Int(height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not allocate preview sheet")
    }
    rep.size = NSSize(width: width, height: height)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.10, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    for (index, variant) in variants.enumerated() {
        let x = margin + CGFloat(index) * tile
        let rendered = scaledImage(variant.image, pixels: 1024)
        rendered.draw(in: NSRect(x: x + 30, y: margin + labelHeight, width: tile - 60, height: tile - 60))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.90),
            .paragraphStyle: paragraph
        ]
        variant.name.draw(in: NSRect(x: x, y: margin, width: tile, height: labelHeight), withAttributes: attrs)
    }

    NSGraphicsContext.current = previous

    let preview = NSImage(size: NSSize(width: width, height: height))
    preview.addRepresentation(rep)
    try savePNG(preview, to: designDir.appendingPathComponent("macvisiontools-icon-variants.png"))
}

let base = centeredSquare(sourceImage)
let variants: [(name: String, slug: String, image: CIImage)] = [
    ("Original", "original", base),
    ("Primary", "primary", applyFilter(base, saturation: 1.08, brightness: 0.01, contrast: 1.06)),
    ("Soft", "soft", applyFilter(base, saturation: 0.92, brightness: 0.02, contrast: 0.96)),
    ("Vibrant", "vibrant", applyFilter(base, saturation: 1.20, brightness: 0.00, contrast: 1.10)),
    ("Muted", "muted", applyFilter(base, saturation: 0.72, brightness: -0.01, contrast: 1.02))
]

let active = variants[1].image
let catalogImages: [(filename: String, pixels: Int)] = [
    ("AppIcon-16.png", 16),
    ("AppIcon-16@2x.png", 32),
    ("AppIcon-32.png", 32),
    ("AppIcon-32@2x.png", 64),
    ("AppIcon-128.png", 128),
    ("AppIcon-128@2x.png", 256),
    ("AppIcon-256.png", 256),
    ("AppIcon-256@2x.png", 512),
    ("AppIcon-512.png", 512),
    ("AppIcon-512@2x.png", 1024)
]

for output in catalogImages {
    try savePNG(scaledImage(active, pixels: output.pixels), to: appIconDir.appendingPathComponent(output.filename))
}

for variant in variants {
    try savePNG(scaledImage(variant.image, pixels: 1024), to: designDir.appendingPathComponent("macvisiontools-\(variant.slug)-1024.png"))
    try savePNG(scaledImage(variant.image, pixels: 512), to: designDir.appendingPathComponent("macvisiontools-\(variant.slug)-512.png"))
}

try drawPreviewSheet(variants.map { ($0.name, $0.image) })

print("Generated old-icon-based AppIcon catalog and \(variants.count) variants.")
