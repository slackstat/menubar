#!/usr/bin/env swift

import AppKit
import CoreGraphics

/// Generates app icon PNGs at all required sizes.
/// Run: swift scripts/generate-icon.swift

let sizes = [16, 32, 128, 256, 512]
let outputDir = "Resources/AppIcon.appiconset"

// Create output directory
let fm = FileManager.default
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("No graphics context")
    }

    // Background: rounded rectangle with blue gradient
    let cornerRadius = s * 0.22
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    context.addPath(path)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.20, green: 0.40, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1.0),
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s), options: [])

    // Draw # symbol in white
    let fontSize = s * 0.55
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: "#", attributes: attributes)
    let strSize = str.size()
    let strOrigin = NSPoint(
        x: (s - strSize.width) / 2,
        y: (s - strSize.height) / 2
    )
    str.draw(at: strOrigin)

    // Red notification dot (upper right)
    let dotRadius = s * 0.10
    let dotCenter = CGPoint(x: s * 0.78, y: s * 0.78)
    context.setFillColor(CGColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1.0))
    context.fillEllipse(in: CGRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    ))

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to create PNG")
    }
    (png as NSData).write(toFile: path, atomically: true)
}

for size in sizes {
    let image = renderIcon(size: size)
    let filename = "icon_\(size)x\(size).png"
    savePNG(image, to: "\(outputDir)/\(filename)")
    print("Generated \(filename)")
}

// Also generate @2x variants for smaller sizes
let retinaMap = [16: 32, 32: 64, 128: 256, 256: 512, 512: 1024]
for (logical, actual) in retinaMap {
    let image = renderIcon(size: actual)
    let filename = "icon_\(logical)x\(logical)@2x.png"
    savePNG(image, to: "\(outputDir)/\(filename)")
    print("Generated \(filename)")
}

// Write Contents.json
let contentsJSON = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contentsJSON.write(toFile: "\(outputDir)/Contents.json", atomically: true, encoding: .utf8)
print("Generated Contents.json")

// Also generate .iconset for iconutil -> .icns conversion
let iconsetDir = "Resources/AppIcon.iconset"
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// iconutil expects specific filenames in the .iconset directory
for size in sizes {
    let image = renderIcon(size: size)
    savePNG(image, to: "\(iconsetDir)/icon_\(size)x\(size).png")
}
for (logical, actual) in retinaMap {
    let image = renderIcon(size: actual)
    savePNG(image, to: "\(iconsetDir)/icon_\(logical)x\(logical)@2x.png")
}

// Run iconutil to create .icns
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    print("Generated AppIcon.icns")
    // Clean up .iconset directory (intermediate artifact)
    try? fm.removeItem(atPath: iconsetDir)
} else {
    print("Warning: iconutil failed (status \(iconutil.terminationStatus)), .icns not generated")
}

print("Done! Icon assets in \(outputDir)/")
