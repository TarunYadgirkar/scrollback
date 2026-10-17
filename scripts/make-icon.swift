// Renders Scrollback's app icon: a day's sessions as bars, one long pink binge with its bracket.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let ink = NSColor(srgbRed: 0x16 / 255, green: 0x18 / 255, blue: 0x1B / 255, alpha: 1)
let session = NSColor(srgbRed: 0x4A / 255, green: 0x4D / 255, blue: 0x53 / 255, alpha: 1)
let signal = NSColor(srgbRed: 0xF0 / 255, green: 0x51 / 255, blue: 0x7F / 255, alpha: 1)

// App Store icons must be opaque. RGBX keeps the bitmap alpha-free; a 3-channel
// NSBitmapImageRep can't back a graphics context, which silently left the icon black.
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
ink.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

/// Rects are given top-down (y from the top) to match how the ribbon reads.
func bar(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: size - top - height, width: width, height: height), xRadius: 14, yRadius: 14).fill()
}

let left: CGFloat = 250
bar(left, 200, 420, 64, session)
bar(left, 290, 280, 40, session)
bar(left, 356, 420, 330, signal)
bar(left, 712, 340, 56, session)
bar(left, 794, 200, 34, session)

let bracket = NSBezierPath()
let bx: CGFloat = 718, top: CGFloat = 356, bottom: CGFloat = 686, cap: CGFloat = 46
bracket.move(to: NSPoint(x: bx + cap, y: size - top))
bracket.line(to: NSPoint(x: bx, y: size - top))
bracket.line(to: NSPoint(x: bx, y: size - bottom))
bracket.line(to: NSPoint(x: bx + cap, y: size - bottom))
bracket.lineWidth = 30
bracket.lineCapStyle = .round
bracket.lineJoinStyle = .round
signal.setStroke()
bracket.stroke()

let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
