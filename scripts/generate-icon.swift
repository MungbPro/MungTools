#!/usr/bin/env swift
// Rebuild with: swift scripts/generate-icon.swift
// Uses only macOS system frameworks and iconutil. No fonts or external assets.
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fileManager = FileManager.default
let temporary = fileManager.temporaryDirectory.appendingPathComponent("MungTools-icon-\(UUID().uuidString)", isDirectory: true)
let iconset = temporary.appendingPathComponent("MungTools.iconset", isDirectory: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporary) }
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let images = root.appendingPathComponent("docs/images", isDirectory: true)
try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
try fileManager.createDirectory(at: images, withIntermediateDirectories: true)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha])!
}
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func path(_ points: [CGPoint], closed: Bool = false) -> CGPath {
    let result = CGMutablePath()
    result.addLines(between: points)
    if closed { result.closeSubpath() }
    return result
}
func gradient(_ context: CGContext, colors: [CGColor], from: CGPoint, to: CGPoint) {
    context.drawLinearGradient(CGGradient(colorsSpace: colorSpace, colors: colors as CFArray,
        locations: nil)!, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func pngWithoutMetadata(_ source: Data) -> Data {
    // AppKit may attach EXIF/profile data; retain only image and standard color chunks.
    let bytes = [UInt8](source)
    var result = Data(bytes.prefix(8))
    var offset = 8
    let keep = Set(["IHDR", "PLTE", "IDAT", "IEND", "tRNS", "sRGB", "gAMA", "cHRM"])
    while offset + 12 <= bytes.count {
        let length = bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        let end = offset + length + 12
        precondition(end <= bytes.count, "Invalid PNG chunk")
        let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii)!
        if keep.contains(type) { result.append(contentsOf: bytes[offset..<end]) }
        offset = end
    }
    precondition(offset == bytes.count, "Invalid PNG length")
    return result
}

func render(size: Int) throws -> Data {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "MungToolsIcon", code: 1)
    }
    let scale = CGFloat(size) / 1024
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: scale, y: -scale)
    context.setAllowsAntialiasing(true)

    let tile = rounded(CGRect(x: 80, y: 80, width: 864, height: 864), radius: 192)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16 * scale), blur: 18 * scale,
        color: color(0x000000, 0.28))
    context.addPath(tile)
    context.setFillColor(color(0x24272E))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile); context.clip()
    gradient(context, colors: [color(0x373A43), color(0x17191F)], from: point(192, 80), to: point(816, 944))
    context.restoreGState()
    context.addPath(rounded(CGRect(x: 81.5, y: 81.5, width: 861, height: 861), radius: 190.5))
    context.setStrokeColor(color(0xFFFFFF, 0.15)); context.setLineWidth(3); context.strokePath()

    let terminal = rounded(CGRect(x: 208, y: 256, width: 608, height: 496), radius: 64)
    context.saveGState()
    context.addPath(terminal); context.clip()
    gradient(context, colors: [color(0x242D38), color(0x111820)], from: point(208, 256), to: point(816, 752))
    context.restoreGState()
    context.addPath(terminal); context.setLineWidth(8)
    context.setStrokeColor(color(0x6B7B8F, 0.48)); context.strokePath()
    context.addPath(path([point(212, 352), point(812, 352)]))
    context.setLineWidth(4); context.setStrokeColor(color(0xA7B5C5, 0.12)); context.strokePath()
    for (index, alpha) in [CGFloat(0.7), 0.45, 0.3].enumerated() {
        context.setFillColor(color(0x8797A8, alpha))
        context.fillEllipse(in: CGRect(x: 250 + index * 36, y: 296, width: 20, height: 20))
    }

    func cyanStroke(_ points: [CGPoint], closed: Bool = false, alpha: CGFloat = 1) {
        context.saveGState()
        context.setLineWidth(28); context.setLineCap(.round); context.setLineJoin(.round)
        context.addPath(path(points, closed: closed)); context.replacePathWithStrokedPath(); context.clip()
        gradient(context, colors: [color(0x70E5FF, alpha), color(0x23B9E0, alpha)],
            from: point(270, 420), to: point(710, 640))
        context.restoreGState()
    }
    cyanStroke([point(284, 452), point(356, 516), point(284, 580)])
    cyanStroke([point(396, 580), point(454, 580)])
    cyanStroke([point(540, 492), point(624, 444), point(708, 492), point(624, 540)], closed: true)
    cyanStroke([point(540, 544), point(624, 592), point(708, 544)], alpha: 0.78)
    cyanStroke([point(540, 596), point(624, 644), point(708, 596)], alpha: 0.53)

    guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image)
        .representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MungToolsIcon", code: 2)
    }
    return pngWithoutMetadata(png)
}

for logicalSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = logicalSize * scale
        let suffix = scale == 1 ? "" : "@2x"
        let data = try render(size: pixels)
        try data.write(to: iconset.appendingPathComponent("icon_\(logicalSize)x\(logicalSize)\(suffix).png"))
        if pixels == 1024 { try data.write(to: images.appendingPathComponent("app-icon.png")) }
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", assets.appendingPathComponent("MungTools.icns").path, iconset.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
print("Generated Assets/MungTools.icns and docs/images/app-icon.png")
