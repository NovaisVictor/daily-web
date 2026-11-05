// Draws the app icon (the web header's navy circle with the green dot).
// Usage: swift Scripts/make-icon.swift /tmp/icon-1024.png, then resize with
// sips into App/Assets.xcassets/AppIcon.appiconset (16…512 pt, @1x and @2x).
import AppKit
import CoreGraphics

// 1024 px canvas, Apple's macOS grid: an 824 px rounded square centered.
let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])! }

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(12, 20, 52)); ctx.fillPath()
ctx.restoreGState()

// Navy gradient like the web header.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(20, 32, 78), rgb(10, 16, 44)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
// Subtle top highlight.
let glow = CGGradient(colorsSpace: cs, colors: [rgb(120, 140, 255, 0.18), rgb(120, 140, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 820), startRadius: 0, endCenter: CGPoint(x: 330, y: 820), endRadius: 520, options: [])
ctx.restoreGState()

// Tile edge.
ctx.addPath(tilePath); ctx.setStrokeColor(rgb(255, 255, 255, 0.10)); ctx.setLineWidth(4); ctx.strokePath()

let center = CGPoint(x: 512, y: 512)
// The header's circle: a lighter disc with a faint ring.
let disc = CGRect(x: center.x - 250, y: center.y - 250, width: 500, height: 500)
ctx.setFillColor(rgb(42, 52, 92, 0.85)); ctx.fillEllipse(in: disc)
ctx.setStrokeColor(rgb(255, 255, 255, 0.16)); ctx.setLineWidth(8); ctx.strokeEllipse(in: disc.insetBy(dx: 4, dy: 4))

// Green dot (brand, oklch(0.72 0.155 158) ≈ #3FBF7F) with a soft glow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: rgb(63, 191, 127, 0.55))
let dot = CGRect(x: center.x - 92, y: center.y - 92, width: 184, height: 184)
ctx.setFillColor(rgb(72, 199, 132)); ctx.fillEllipse(in: dot)
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
