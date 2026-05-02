import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceDir = root.appendingPathComponent("screenshots", isDirectory: true)
let imageDir = root.appendingPathComponent("images", isDirectory: true)
let appStoreDir = root.appendingPathComponent("app-store/screenshots/en-US/mac-2880x1800", isDirectory: true)

try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: appStoreDir, withIntermediateDirectories: true)

struct Shot {
    let file: String
    let title: String
    let subtitle: String
    let accent: NSColor
    let cropTop: CGFloat
    let cropBottom: CGFloat
    let cropLeft: CGFloat
    let cropRight: CGFloat
}

let standard = Shot(file: "standard.png", title: "Live object detection.", subtitle: "Run SSD MobileNet V2 or drop in your own Core ML detector.", accent: .systemOrange, cropTop: 30, cropBottom: 4, cropLeft: 22, cropRight: 4)
let emotion = Shot(file: "emotion vibes.png", title: "Emotion cues on device.", subtitle: "Apple Vision finds faces, then Emotieff classifies the visible expression.", accent: .systemPink, cropTop: 32, cropBottom: 4, cropLeft: 22, cropRight: 4)
let privacy = Shot(file: "privacy.png", title: "Privacy guardrails.", subtitle: "Count visible people and start the macOS screen saver at your threshold.", accent: .systemRed, cropTop: 28, cropBottom: 4, cropLeft: 18, cropRight: 4)
let focus = Shot(file: "focus.png", title: "Native focus tracking.", subtitle: "Apple Vision head-pose tracking, no extra model required.", accent: .systemBlue, cropTop: 12, cropBottom: 4, cropLeft: 18, cropRight: 4)

func bitmap(_ size: CGSize) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = size
    return rep
}

func draw(in rep: NSBitmapImageRep, _ block: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    block()
    NSGraphicsContext.restoreGraphicsState()
}

func save(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MacVisionToolsScreenshots", code: 1)
    }
    try data.write(to: url)
}

func rounded(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 2) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func text(_ value: String, rect: CGRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, lineHeight: CGFloat? = nil) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    if let lineHeight {
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
    }
    NSString(string: value).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style
    ])
}

func background(size: CGSize, accent: NSColor) {
    NSGradient(colors: [
        NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.075, alpha: 1),
        NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.13, alpha: 1)
    ])!.draw(in: CGRect(origin: .zero, size: size), angle: 315)

    accent.withAlphaComponent(0.24).setFill()
    NSBezierPath(ovalIn: CGRect(x: size.width * 0.58, y: size.height * 0.54, width: size.width * 0.30, height: size.width * 0.30)).fill()
    NSColor.systemGreen.withAlphaComponent(0.16).setFill()
    NSBezierPath(ovalIn: CGRect(x: size.width * 0.66, y: size.height * 0.18, width: size.width * 0.22, height: size.width * 0.22)).fill()

    NSColor(calibratedWhite: 1, alpha: 0.035).setStroke()
    for x in stride(from: CGFloat(0), through: size.width, by: 120) {
        let line = NSBezierPath()
        line.move(to: CGPoint(x: x, y: 0))
        line.line(to: CGPoint(x: x, y: size.height))
        line.stroke()
    }
}

func image(for shot: Shot) throws -> NSImage {
    let url = sourceDir.appendingPathComponent(shot.file)
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "MacVisionToolsScreenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing screenshot: \(url.path)"])
    }
    return image
}

func drawSource(_ shot: Shot, in rect: CGRect) throws {
    let source = try image(for: shot)
    let sourceSize = source.size
    let crop = CGRect(
        x: shot.cropLeft,
        y: shot.cropBottom,
        width: sourceSize.width - shot.cropLeft - shot.cropRight,
        height: sourceSize.height - shot.cropTop - shot.cropBottom
    )
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = CGSize(width: 0, height: -18)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    rounded(rect.insetBy(dx: 8, dy: 8), radius: 42, fill: .black.withAlphaComponent(0.26))
    NSGraphicsContext.restoreGraphicsState()

    source.draw(in: rect, from: crop, operation: .sourceOver, fraction: 1)
}

func websiteImage(_ shot: Shot, output: String) throws {
    let size = CGSize(width: 1196, height: 1268)
    let rep = bitmap(size)
    draw(in: rep) {
        background(size: size, accent: shot.accent)
        let h: CGFloat = 1188
        let sourceWidth = 608 - shot.cropLeft - shot.cropRight
        let sourceHeight = 1158 - shot.cropTop - shot.cropBottom
        let w = h * sourceWidth / sourceHeight
        try? drawSource(shot, in: CGRect(x: (size.width - w) / 2, y: 40, width: w, height: h))
    }
    try save(rep, to: imageDir.appendingPathComponent(output))
}

func framedShot(_ shot: Shot, rect: CGRect, label: String? = nil) throws {
    rounded(rect, radius: 34, fill: NSColor(calibratedRed: 0.08, green: 0.095, blue: 0.12, alpha: 1), stroke: NSColor(calibratedWhite: 1, alpha: 0.12))
    let top = CGRect(x: rect.minX, y: rect.maxY - 62, width: rect.width, height: 62)
    rounded(top, radius: 34, fill: NSColor(calibratedWhite: 1, alpha: 0.055))
    [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated().forEach { index, color in
        color.withAlphaComponent(0.88).setFill()
        NSBezierPath(ovalIn: CGRect(x: rect.minX + 34 + CGFloat(index) * 30, y: rect.maxY - 38, width: 14, height: 14)).fill()
    }
    if let label {
        text(label, rect: CGRect(x: rect.minX + 132, y: rect.maxY - 48, width: rect.width - 170, height: 26), size: 20, weight: .regular, color: NSColor(calibratedWhite: 0.72, alpha: 1))
    }
    let content = rect.insetBy(dx: 44, dy: 92)
    let h = content.height
    let sourceWidth = 608 - shot.cropLeft - shot.cropRight
    let sourceHeight = 1158 - shot.cropTop - shot.cropBottom
    let w = h * sourceWidth / sourceHeight
    try drawSource(shot, in: CGRect(x: content.midX - w / 2, y: content.minY, width: w, height: h))
}

func pill(_ value: String, x: CGFloat, y: CGFloat, color: NSColor) {
    let rect = CGRect(x: x, y: y, width: 560, height: 82)
    rounded(rect, radius: 26, fill: color.withAlphaComponent(0.14), stroke: color.withAlphaComponent(0.55), lineWidth: 3)
    text(value, rect: rect.insetBy(dx: 30, dy: 21), size: 30, weight: .semibold, color: NSColor(calibratedWhite: 0.96, alpha: 1))
}

func featureBlock(_ title: String, detail: String, x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor) {
    let rect = CGRect(x: x, y: y, width: width, height: 118)
    rounded(rect, radius: 26, fill: color.withAlphaComponent(0.14), stroke: color.withAlphaComponent(0.48), lineWidth: 3)
    text(title, rect: CGRect(x: rect.minX + 30, y: rect.minY + 66, width: rect.width - 60, height: 34), size: 30, weight: .bold, color: NSColor(calibratedWhite: 0.96, alpha: 1))
    text(detail, rect: CGRect(x: rect.minX + 30, y: rect.minY + 24, width: rect.width - 60, height: 38), size: 25, weight: .regular, color: NSColor(calibratedWhite: 0.72, alpha: 1), lineHeight: 31)
}

func appStoreSingle(_ name: String, shot: Shot, title: String, subtitle: String, features: [(String, String)], accent: NSColor) throws {
    let size = CGSize(width: 2880, height: 1800)
    let rep = bitmap(size)
    draw(in: rep) {
        background(size: size, accent: accent)
        text("Mac Vision Tools", rect: CGRect(x: 180, y: 1532, width: 780, height: 42), size: 34, weight: .bold, color: accent)
        text(title, rect: CGRect(x: 170, y: 1182, width: 1180, height: 300), size: 118, weight: .bold, color: NSColor(calibratedWhite: 0.96, alpha: 1), lineHeight: 126)
        text(subtitle, rect: CGRect(x: 176, y: 990, width: 1030, height: 150), size: 44, weight: .regular, color: NSColor(calibratedWhite: 0.74, alpha: 1), lineHeight: 58)
        for (index, feature) in features.enumerated() {
            featureBlock(feature.0, detail: feature.1, x: 178, y: 775 - CGFloat(index) * 140, width: 760, color: index == 0 ? accent : .systemGreen)
        }
        try? framedShot(shot, rect: CGRect(x: 1540, y: 150, width: 910, height: 1500), label: title.replacingOccurrences(of: ".", with: ""))
    }
    try save(rep, to: appStoreDir.appendingPathComponent(name))
}

func overview() throws {
    let size = CGSize(width: 2880, height: 1800)
    let rep = bitmap(size)
    draw(in: rep) {
        background(size: size, accent: .systemTeal)
        text("Mac Vision Tools", rect: CGRect(x: 176, y: 1202, width: 1160, height: 280), size: 124, weight: .bold, color: NSColor(calibratedWhite: 0.96, alpha: 1), lineHeight: 132)
        text("Local Core ML vision from the macOS menu bar.", rect: CGRect(x: 182, y: 1038, width: 1040, height: 120), size: 48, weight: .regular, color: NSColor(calibratedWhite: 0.74, alpha: 1), lineHeight: 62)
        featureBlock("Runs on your Mac", detail: "No accounts, analytics, or server upload.", x: 184, y: 810, width: 780, color: .systemGreen)
        featureBlock("Camera or screen", detail: "Use live camera input or ScreenCaptureKit.", x: 184, y: 670, width: 780, color: .systemOrange)
        featureBlock("Bundled and custom models", detail: "Start with included models or select Core ML files.", x: 184, y: 530, width: 780, color: .systemBlue)
        try? framedShot(standard, rect: CGRect(x: 1480, y: 160, width: 900, height: 1480), label: "Menu bar controls")
    }
    try save(rep, to: appStoreDir.appendingPathComponent("01-overview.png"))
}

try websiteImage(standard, output: "standard.png")
try websiteImage(emotion, output: "emotion.png")
try websiteImage(privacy, output: "privacy.png")
try websiteImage(focus, output: "focus.png")

try overview()
try appStoreSingle(
    "02-object-detection.png",
    shot: standard,
    title: "Detect objects live.",
    subtitle: "Run SSD MobileNet V2 on camera or screen input, with a window or overlay preview.",
    features: [
        ("80 COCO classes", "Includes person, laptop, phone, and more."),
        ("Custom Core ML", "Drop in your own detector for experiments."),
        ("Adjustable threshold", "Tune confidence and frame rate from the panel.")
    ],
    accent: .systemOrange
)
try appStoreSingle(
    "03-emotion-vibes.png",
    shot: emotion,
    title: "Read face emotion cues.",
    subtitle: "Faces are detected first, then classified locally with the bundled emotion model.",
    features: [
        ("Face-first pipeline", "Apple Vision finds the face crop before inference."),
        ("Local history", "Keep a short view of recent emotion results."),
        ("On-device model", "No camera frames are uploaded.")
    ],
    accent: .systemPink
)
try appStoreSingle(
    "04-privacy-guard.png",
    shot: privacy,
    title: "Trigger privacy guardrails.",
    subtitle: "Count visible people locally and start the macOS screen saver when your threshold is reached.",
    features: [
        ("Person threshold", "Choose when Privacy Guard should act."),
        ("Local detection", "People are counted on device."),
        ("macOS lock control", "Your system setting decides password behavior.")
    ],
    accent: .systemRed
)
try appStoreSingle(
    "05-local-models.png",
    shot: focus,
    title: "Track focus without a model.",
    subtitle: "Apple Vision head-pose tracking powers focused-time sessions without uploading frames.",
    features: [
        ("Native Vision", "No custom model required for Focus Timer."),
        ("Session targets", "Choose 15, 25, 45, or 60 minute goals."),
        ("Live feedback", "See focused state and session progress.")
    ],
    accent: .systemBlue
)

print("Composited real screenshots into website and App Store assets.")
