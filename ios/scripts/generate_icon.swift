// Generuje ikonę aplikacji w wyglądzie „Grafit”: wiersze faktury przechodzące w strzałkę przelewu.
// Trzy warianty dla iOS: jasny (miętowe tło), ciemny (grafit) i barwiony (skala szarości).
//
//   swift scripts/generate_icon.swift KSeFektywnie/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: cs, components: [Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255,
                                         Double(hex & 0xFF) / 255, 1])!
}

struct Variant {
    let fileName: String
    let background: UInt32
    let lines: UInt32
    let arrow: UInt32
}

let variants = [
    Variant(fileName: "AppIcon.png", background: 0x6EF0B2, lines: 0x0F1211, arrow: 0x0F1211),
    Variant(fileName: "AppIcon-dark.png", background: 0x0F1211, lines: 0xECF1EE, arrow: 0x6EF0B2),
    Variant(fileName: "AppIcon-tinted.png", background: 0x000000, lines: 0xB8B8B8, arrow: 0xFFFFFF),
]

// Geometria w siatce 240 × 240 (jak na makiecie), oś Y w dół.
let unit = size / 240
func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * unit, y: size - y * unit) }

for variant in variants {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(color(variant.background))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setLineWidth(18 * unit)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Dwa wiersze faktury.
    ctx.setStrokeColor(color(variant.lines))
    ctx.move(to: point(62, 70)); ctx.addLine(to: point(140, 70))
    ctx.move(to: point(62, 108)); ctx.addLine(to: point(112, 108))
    ctx.strokePath()

    // Trzeci wiersz zamienia się w strzałkę.
    ctx.setStrokeColor(color(variant.arrow))
    ctx.move(to: point(62, 146)); ctx.addLine(to: point(176, 146))
    ctx.move(to: point(146, 118)); ctx.addLine(to: point(176, 146)); ctx.addLine(to: point(146, 174))
    ctx.strokePath()

    let url = directory.appendingPathComponent(variant.fileName)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Nie udało się zapisać \(url.path)") }
    print("Zapisano \(variant.fileName)")
}
