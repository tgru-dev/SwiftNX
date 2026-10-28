#!/usr/bin/env swift

import AppKit
import Foundation

// Draws the SwiftNX app icon without external assets and writes:
//   <output>/AppIcon.icns, <output>/AppIcon.png and an .iconset folder.
// Usage: swift Scripts/make-icon.swift Resources

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources", isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let side: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: side, height: side))

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

canvas.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()

let iconRect = NSRect(x: 70, y: 70, width: 884, height: 884)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 205, yRadius: 205)

// Soft ambient shadow around the squircle.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
shadow.shadowBlurRadius = 50
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
color(20, 28, 78).setFill()
iconPath.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [
    color(27, 35, 92),
    color(57, 84, 232),
    color(73, 152, 255),
])!
gradient.draw(in: iconPath, angle: -58)

// Diagonal sheen.
NSGraphicsContext.saveGraphicsState()
iconPath.addClip()
let sheen = NSBezierPath()
sheen.move(to: NSPoint(x: 70, y: 800))
sheen.line(to: NSPoint(x: 955, y: 250))
sheen.line(to: NSPoint(x: 955, y: 955))
sheen.line(to: NSPoint(x: 100, y: 955))
sheen.close()
color(255, 255, 255, 0.085).setFill()
sheen.fill()
NSGraphicsContext.restoreGraphicsState()

// Inner highlight.
let border = NSBezierPath(roundedRect: iconRect.insetBy(dx: 5, dy: 5), xRadius: 200, yRadius: 200)
color(255, 255, 255, 0.20).setStroke()
border.lineWidth = 3
border.stroke()

func tinted(_ image: NSImage, with tint: NSColor) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
    tint.setFill()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    result.unlockFocus()
    return result
}

// Game controller glyph.
let configuration = NSImage.SymbolConfiguration(pointSize: 405, weight: .medium)
if let rawSymbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) {
    let symbol = tinted(rawSymbol, with: .white)
    let symbolSize = symbol.size
    let scale = min(560 / symbolSize.width, 480 / symbolSize.height)
    let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
    let drawRect = NSRect(
        x: (side - drawSize.width) / 2,
        y: (side - drawSize.height) / 2 + 8,
        width: drawSize.width,
        height: drawSize.height
    )
    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    glyphShadow.shadowBlurRadius = 18
    glyphShadow.shadowOffset = NSSize(width: 0, height: -8)
    glyphShadow.set()
    symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 0.97)
    NSGraphicsContext.restoreGraphicsState()
}

// Small mint status accent.
let dotRect = NSRect(x: 718, y: 704, width: 112, height: 112)
let dot = NSBezierPath(ovalIn: dotRect)
NSGraphicsContext.saveGraphicsState()
let dotShadow = NSShadow()
dotShadow.shadowColor = color(45, 235, 180, 0.65)
dotShadow.shadowBlurRadius = 22
dotShadow.set()
color(69, 231, 178).setFill()
dot.fill()
NSGraphicsContext.restoreGraphicsState()
color(20, 45, 50, 0.75).setStroke()
dot.lineWidth = 2
dot.stroke()

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("Could not render the icon.\n".utf8))
    exit(1)
}

let masterURL = outputDirectory.appendingPathComponent("AppIcon.png")
try png.write(to: masterURL)

let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in variants {
    let target = NSImage(size: NSSize(width: pixels, height: pixels))
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    canvas.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(x: 0, y: 0, width: side, height: side),
        operation: .copy,
        fraction: 1
    )
    target.unlockFocus()
    guard let data = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: data),
          let scaled = rep.representation(using: .png, properties: [:])
    else { continue }
    try scaled.write(to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
if iconutil.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed.\n".utf8))
    exit(iconutil.terminationStatus)
}

print("Wrote \(masterURL.path)")
print("Wrote \(outputDirectory.appendingPathComponent("AppIcon.icns").path)")
