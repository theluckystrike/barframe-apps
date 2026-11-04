import AppKit
import CoreGraphics

// Original tray and document shapes, drawn directly with Core Graphics.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.addPath(CGPath(roundedRect: CGRect(x: 20, y: 20, width: 984, height: 984), cornerWidth: 218, cornerHeight: 218, transform: nil)); ctx.clip()
let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.12, green: 0.5, blue: 0.98, alpha: 1), CGColor(red: 0.03, green: 0.23, blue: 0.68, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 950), end: CGPoint(x: 850, y: 50), options: [])
func round(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor) { ctx.setFillColor(color); ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.fillPath() }
ctx.saveGState(); ctx.translateBy(x: 435, y: 570); ctx.rotate(by: -.pi / 16)
round(CGRect(x: -135, y: -155, width: 270, height: 340), 30, CGColor(gray: 1, alpha: 1))
for index in 0..<3 { round(CGRect(x: -85, y: 90 - index * 55, width: index == 2 ? 105 : 170, height: 18), 9, CGColor(red: 0.16, green: 0.43, blue: 0.78, alpha: 1)) }
ctx.restoreGState()
ctx.saveGState(); ctx.translateBy(x: 660, y: 555); ctx.rotate(by: .pi / 14)
round(CGRect(x: -110, y: -110, width: 220, height: 240), 34, CGColor(red: 0.33, green: 0.88, blue: 0.89, alpha: 1))
ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: -65, y: 38, width: 36, height: 36))
let mountain = CGMutablePath(); mountain.move(to: CGPoint(x: -85, y: -70)); mountain.addLine(to: CGPoint(x: -5, y: 40)); mountain.addLine(to: CGPoint(x: 85, y: -70)); mountain.closeSubpath(); ctx.addPath(mountain);ctx.fillPath();ctx.restoreGState()
// Continuous, bold U-shaped tray remains legible at small sizes.
let tray = CGMutablePath(); tray.move(to: CGPoint(x: 200, y: 445)); tray.addLine(to: CGPoint(x: 200, y: 280)); tray.addQuadCurve(to: CGPoint(x: 285, y: 195), control: CGPoint(x: 200, y: 195)); tray.addLine(to: CGPoint(x: 745, y: 195));tray.addQuadCurve(to: CGPoint(x: 830, y: 280), control: CGPoint(x: 830, y: 195));tray.addLine(to: CGPoint(x: 830, y: 445))
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1));ctx.setLineWidth(72);ctx.setLineCap(.round);ctx.addPath(tray);ctx.strokePath()
let image = ctx.makeImage()!
try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: output)
