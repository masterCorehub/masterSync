import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: swift draw-app-icon.swift <source-image> <output-1024.png>\n", stderr)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let nsImage = NSImage(contentsOf: sourceURL),
      let sourceCG = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Failed to load source image at \(sourceURL.path)\n", stderr)
    exit(1)
}

let size = 1024
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: size, height: size))

let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185
let tilePath = CGPath(roundedRect: tileRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Subtle macOS Dock drop shadow behind the squircle
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.36))
context.setFillColor(CGColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1))
context.addPath(tilePath)
context.fillPath()
context.restoreGState()

// Clip to squircle and draw full-bleed artwork scaled cleanly
context.saveGState()
context.addPath(tilePath)
context.clip()
context.interpolationQuality = .high

// Aspect-fill source image into tileRect
let srcW = CGFloat(sourceCG.width)
let srcH = CGFloat(sourceCG.height)
let scale = max(tileRect.width / srcW, tileRect.height / srcH)
let drawW = srcW * scale
let drawH = srcH * scale
let drawRect = CGRect(
    x: tileRect.midX - drawW / 2,
    y: tileRect.midY - drawH / 2,
    width: drawW,
    height: drawH
)
context.draw(sourceCG, in: drawRect)

// Delicate glass inner rim stroke inside the clipped squircle
let rimRect = tileRect.insetBy(dx: 0.75, dy: 0.75)
let rimPath = CGPath(roundedRect: rimRect, cornerWidth: cornerRadius - 0.75, cornerHeight: cornerRadius - 0.75, transform: nil)
context.addPath(rimPath)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
context.setLineWidth(1.5)
context.strokePath()
context.restoreGState()

guard let outputCG = context.makeImage() else {
    fputs("Failed to render output CGImage\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: outputCG)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: destinationURL, options: .atomic)
