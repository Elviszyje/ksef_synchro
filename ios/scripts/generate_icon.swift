// Generuje tymczasową ikonę aplikacji (placeholder do czasu projektu graficznego):
//   swift scripts/generate_icon.swift KSeFektywnie/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png [dark]

import AppKit
import CoreGraphics

let size = 1024.0
let out = CommandLine.arguments[1]
let dark = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "dark"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

// Tło: gradient granat → niebieski (akcent aplikacji #1A56DB).
let top = dark ? color(0.06, 0.09, 0.20) : color(0.16, 0.42, 0.95)
let bottom = dark ? color(0.02, 0.03, 0.08) : color(0.06, 0.20, 0.62)
let gradient = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Dokument z zagiętym rogiem.
let doc = CGRect(x: 262, y: 170, width: 440, height: 600)
let fold = 130.0
let page = CGMutablePath()
page.move(to: CGPoint(x: doc.minX + 36, y: doc.minY))
page.addLine(to: CGPoint(x: doc.maxX - 36, y: doc.minY))
page.addQuadCurve(to: CGPoint(x: doc.maxX, y: doc.minY + 36), control: CGPoint(x: doc.maxX, y: doc.minY))
page.addLine(to: CGPoint(x: doc.maxX, y: doc.maxY - fold))
page.addLine(to: CGPoint(x: doc.maxX - fold, y: doc.maxY))
page.addLine(to: CGPoint(x: doc.minX + 36, y: doc.maxY))
page.addQuadCurve(to: CGPoint(x: doc.minX, y: doc.maxY - 36), control: CGPoint(x: doc.minX, y: doc.maxY))
page.addLine(to: CGPoint(x: doc.minX, y: doc.minY + 36))
page.addQuadCurve(to: CGPoint(x: doc.minX + 36, y: doc.minY), control: CGPoint(x: doc.minX, y: doc.minY))
page.closeSubpath()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0, 0, 0, 0.30))
ctx.addPath(page)
ctx.setFillColor(dark ? color(0.93, 0.95, 1.0) : color(1, 1, 1))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Zagięty róg.
let corner = CGMutablePath()
corner.move(to: CGPoint(x: doc.maxX, y: doc.maxY - fold))
corner.addLine(to: CGPoint(x: doc.maxX - fold + 18, y: doc.maxY - fold))
corner.addQuadCurve(to: CGPoint(x: doc.maxX - fold, y: doc.maxY - fold + 18), control: CGPoint(x: doc.maxX - fold, y: doc.maxY - fold))
corner.addLine(to: CGPoint(x: doc.maxX - fold, y: doc.maxY))
corner.closeSubpath()
ctx.addPath(corner)
ctx.setFillColor(color(0.78, 0.84, 0.96))
ctx.fillPath()

// Linie tekstu.
ctx.setFillColor(color(0.70, 0.77, 0.90))
for (i, w) in [300.0, 250.0, 280.0].enumerated() {
    let y = doc.maxY - 210 - Double(i) * 70
    ctx.addPath(CGPath(roundedRect: CGRect(x: doc.minX + 70, y: y, width: w, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil))
    ctx.fillPath()
}

// Znacznik "zaksięgowane": zielone koło z haczykiem.
let badge = CGRect(x: 560, y: 150, width: 300, height: 300)
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0, 0, 0, 0.30))
ctx.setFillColor(color(0.13, 0.75, 0.42))
ctx.fillEllipse(in: badge)
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setStrokeColor(color(1, 1, 1))
ctx.setLineWidth(42)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: badge.minX + 80, y: badge.midY + 2))
ctx.addLine(to: CGPoint(x: badge.minX + 132, y: badge.midY - 52))
ctx.addLine(to: CGPoint(x: badge.maxX - 72, y: badge.midY + 62))
ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("ok \(out)")
