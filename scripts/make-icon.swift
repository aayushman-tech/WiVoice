import AppKit
import CoreGraphics
import Foundation

let output = CommandLine.arguments[1]
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                      bytesPerRow: size * 4, space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let bounds = CGRect(x: 0, y: 0, width: size, height: size)

bitmap.setFillColor(NSColor(calibratedRed: 0.10, green: 0.39, blue: 0.96, alpha: 1).cgColor)
bitmap.addPath(CGPath(roundedRect: bounds.insetBy(dx: 20, dy: 20), cornerWidth: 225,
                      cornerHeight: 225, transform: nil))
bitmap.fillPath()

bitmap.setStrokeColor(NSColor.white.cgColor)
bitmap.setLineCap(.round)
bitmap.setLineWidth(52)
let bars: [(CGFloat, CGFloat)] = [
    (292, 470), (402, 620), (512, 800), (622, 620), (732, 470)
]
for (x, height) in bars {
    bitmap.move(to: CGPoint(x: x, y: (CGFloat(size) - height) / 2))
    bitmap.addLine(to: CGPoint(x: x, y: (CGFloat(size) + height) / 2))
}
bitmap.strokePath()

let image = bitmap.makeImage()!
let representation = NSBitmapImageRep(cgImage: image)
let png = representation.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
