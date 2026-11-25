import AppKit
import CoreGraphics

let destination = CommandLine.arguments[1]
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 0.16, green: 0.105, blue: 0.075, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 92, y: 92, width: 840, height: 840),
                       cornerWidth: 185, cornerHeight: 185, transform: nil))
context.fillPath()
context.setStrokeColor(CGColor(red: 0.69, green: 0.47, blue: 0.31, alpha: 1))
context.setLineWidth(35)
context.addPath(CGPath(roundedRect: CGRect(x: 222, y: 235, width: 580, height: 554),
                       cornerWidth: 100, cornerHeight: 100, transform: nil))
context.strokePath()
context.setLineWidth(49)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setStrokeColor(CGColor(red: 0.95, green: 0.73, blue: 0.49, alpha: 1))
func arrow(_ begin: CGFloat, _ end: CGFloat, y: CGFloat, back: CGFloat) {
    context.move(to: CGPoint(x: begin, y: y))
    context.addLine(to: CGPoint(x: end, y: y))
    context.move(to: CGPoint(x: end + back, y: y + 77))
    context.addLine(to: CGPoint(x: end, y: y))
    context.addLine(to: CGPoint(x: end + back, y: y - 77))
    context.strokePath()
}
arrow(326, 679, y: 604, back: -78)
arrow(699, 346, y: 420, back: 78)
let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
