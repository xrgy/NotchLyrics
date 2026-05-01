#!/usr/bin/env swift
import AppKit
import Foundation

let appName = "NotchLyrics"
let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let packagingURL = rootURL.appendingPathComponent("packaging")
let iconsetURL = packagingURL.appendingPathComponent("\(appName).iconset")
let outputURL = packagingURL.appendingPathComponent("\(appName).icns")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func scaledRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, canvas: CGFloat) -> NSRect {
    NSRect(
        x: x / 1024 * canvas,
        y: y / 1024 * canvas,
        width: width / 1024 * canvas,
        height: height / 1024 * canvas
    )
}

func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fillRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    roundedPath(rect, radius: radius).fill()
}

func strokeRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor, lineWidth: CGFloat) {
    let path = roundedPath(rect, radius: radius)
    path.lineWidth = lineWidth
    color.setStroke()
    path.stroke()
}

func drawMusicNote(in rect: NSRect, scale: CGFloat) {
    color(0.98, 0.94, 0.84).setFill()

    let head = NSBezierPath(ovalIn: NSRect(
        x: rect.minX + 18 * scale,
        y: rect.minY + 16 * scale,
        width: 48 * scale,
        height: 34 * scale
    ))
    head.fill()

    fillRoundedRect(
        NSRect(x: rect.minX + 58 * scale, y: rect.minY + 32 * scale, width: 13 * scale, height: 92 * scale),
        radius: 6 * scale,
        color: color(0.98, 0.94, 0.84)
    )

    let flag = NSBezierPath()
    flag.move(to: NSPoint(x: rect.minX + 68 * scale, y: rect.minY + 116 * scale))
    flag.curve(
        to: NSPoint(x: rect.minX + 118 * scale, y: rect.minY + 92 * scale),
        controlPoint1: NSPoint(x: rect.minX + 92 * scale, y: rect.minY + 116 * scale),
        controlPoint2: NSPoint(x: rect.minX + 112 * scale, y: rect.minY + 108 * scale)
    )
    flag.line(to: NSPoint(x: rect.minX + 118 * scale, y: rect.minY + 70 * scale))
    flag.curve(
        to: NSPoint(x: rect.minX + 70 * scale, y: rect.minY + 92 * scale),
        controlPoint1: NSPoint(x: rect.minX + 106 * scale, y: rect.minY + 86 * scale),
        controlPoint2: NSPoint(x: rect.minX + 88 * scale, y: rect.minY + 94 * scale)
    )
    flag.close()
    flag.fill()
}

func makeIcon(size: Int) throws -> NSImage {
    let canvas = CGFloat(size)
    let scale = canvas / 1024
    let image = NSImage(size: NSSize(width: canvas, height: canvas))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

    let background = scaledRect(64, 64, 896, 896, canvas: canvas)
    let backgroundPath = roundedPath(background, radius: 210 * scale)
    backgroundPath.addClip()

    NSGradient(colors: [
        color(0.06, 0.07, 0.09),
        color(0.13, 0.16, 0.22),
        color(0.03, 0.035, 0.045)
    ])?.draw(in: backgroundPath, angle: 315)

    fillRoundedRect(
        scaledRect(276, 714, 472, 120, canvas: canvas),
        radius: 58 * scale,
        color: color(0.005, 0.006, 0.008, 0.96)
    )

    let capsule = scaledRect(150, 326, 724, 330, canvas: canvas)
    fillRoundedRect(capsule, radius: 142 * scale, color: color(0.02, 0.023, 0.032, 0.98))
    strokeRoundedRect(capsule, radius: 142 * scale, color: color(1, 1, 1, 0.12), lineWidth: 7 * scale)

    let album = scaledRect(236, 422, 164, 164, canvas: canvas)
    fillRoundedRect(album, radius: 38 * scale, color: color(0.97, 0.48, 0.20))
    NSGradient(colors: [
        color(1.00, 0.63, 0.30),
        color(0.94, 0.27, 0.26)
    ])?.draw(in: roundedPath(album, radius: 38 * scale), angle: 295)
    strokeRoundedRect(album, radius: 38 * scale, color: color(1, 1, 1, 0.18), lineWidth: 5 * scale)
    drawMusicNote(in: album, scale: scale)

    fillRoundedRect(
        scaledRect(462, 530, 316, 34, canvas: canvas),
        radius: 17 * scale,
        color: color(0.98, 0.94, 0.84, 0.95)
    )
    fillRoundedRect(
        scaledRect(462, 468, 240, 28, canvas: canvas),
        radius: 14 * scale,
        color: color(0.98, 0.94, 0.84, 0.42)
    )

    fillRoundedRect(
        scaledRect(770, 436, 18, 96, canvas: canvas),
        radius: 9 * scale,
        color: color(0.32, 0.84, 0.63, 0.90)
    )
    fillRoundedRect(
        scaledRect(804, 404, 18, 128, canvas: canvas),
        radius: 9 * scale,
        color: color(0.32, 0.84, 0.63, 0.72)
    )

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: appName, code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render PNG"])
    }

    try pngData.write(to: url)
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try FileManager.default.createDirectory(at: packagingURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (filename, size) in specs {
    try writePNG(makeIcon(size: size), to: iconsetURL.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: appName, code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

try? FileManager.default.removeItem(at: iconsetURL)
print("Generated \(outputURL.path)")
