#!/usr/bin/env swift
//
// Generates QuickPad's AppIcon set procedurally — an *Ephemeris*
// composition: hairline horizontal strata fading into the substrate,
// with a single cinnabar mark dignifying the present moment. See
// docs/icon-philosophy.md for the design philosophy this expresses.
//
// Usage:  swift scripts/generate-icon.swift
//
// Writes PNGs into QuickPad/Resources/Assets.xcassets/AppIcon.appiconset/
// at every size the asset catalog needs and rewrites Contents.json so
// each slot's declared dimensions match its physical pixels.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Palette
//
// Warm parchment, sumi-ink dark, oxidised cinnabar — the same three
// tones as the philosophy poster. The discipline of working with three
// colors (and only one of them as accent) is what gives the cinnabar
// mark its weight.

let parchmentTop    = NSColor(red: 246/255, green: 240/255, blue: 228/255, alpha: 1.0)
let parchmentBottom = NSColor(red: 232/255, green: 224/255, blue: 209/255, alpha: 1.0)
let sumi            = NSColor(red:  28/255, green:  25/255, blue:  22/255, alpha: 1.0)
let cinnabar        = NSColor(red: 172/255, green:  56/255, blue:  44/255, alpha: 1.0)

// MARK: - Renderer

func renderIcon(size: CGFloat) -> NSImage {
    let canvas = NSSize(width: size, height: size)
    let image = NSImage(size: canvas)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // --- Background squircle (Big Sur+ corner ≈ 22.37% of side) ---
    let cornerRadius = size * 0.2237
    let bgRect = CGRect(origin: .zero, size: canvas)
    let bgPath = CGPath(
        roundedRect: bgRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.addPath(bgPath); ctx.setFillColor(parchmentBottom.cgColor); ctx.fillPath()

    // Whisper of a top→bottom gradient — keeps the surface from reading
    // as a flat swatch at large sizes.
    ctx.saveGState()
    ctx.addPath(bgPath); ctx.clip()
    if let g = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [parchmentTop.cgColor, parchmentBottom.cgColor] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            g,
            start: CGPoint(x: 0, y: size),
            end: .zero,
            options: []
        )
    }
    ctx.restoreGState()

    // --- The strata ---
    //
    // Seven equal-length hairlines stratified vertically. The topmost
    // is the cinnabar — the day's marked observation. Beneath it,
    // sumi lines dissolve in opacity (gravity decay).
    //
    // Critically, lengths are uniform: in QuickPad's data model,
    // `gravityOpacity` is a pure function of `ageInDays`. An entry's
    // text length has nothing to do with its age. Tapering line
    // length top-to-bottom would tell a false story ("older notes
    // are shorter"). Opacity alone carries the decay.
    //
    //  ▔▔▔▔▔▔▔▔▔▔▔▔▔▔  ← cinnabar (today)
    //  ▔▔▔▔▔▔▔▔▔▔▔▔▔▔
    //  ▔▔▔▔▔▔▔▔▔▔▔▔▔▔
    //  ▔▔▔▔▔▔▔▔▔▔▔▔▔▔  (each fainter than the one above)
    //  ▔▔▔▔▔▔▔▔▔▔▔▔▔▔
    //  ▔▔▔▔▔▔▔▔▔▔▔▔▔▔
    //  ▔▔▔▔▔▔▔▔▔▔▔▔▔▔
    //
    // Cocoa coords — origin bottom-left.
    let strataWidth: CGFloat = 0.66
    let strata: [(y: CGFloat, alpha: CGFloat, isAccent: Bool)] = [
        (y: 0.770, alpha: 1.00, isAccent: true ),
        (y: 0.680, alpha: 0.82, isAccent: false),
        (y: 0.590, alpha: 0.62, isAccent: false),
        (y: 0.500, alpha: 0.46, isAccent: false),
        (y: 0.410, alpha: 0.32, isAccent: false),
        (y: 0.320, alpha: 0.22, isAccent: false),
        (y: 0.230, alpha: 0.14, isAccent: false),
    ]

    // Stroke widths — hairline relative to canvas. Floored to 1px so
    // the lines don't disappear at 16×16. The accent gets a single
    // notch more weight, never enough to feel heavy.
    let strokeBase   = max(1.0, (size * 0.0050).rounded())
    let strokeAccent = max(1.0, (size * 0.0062).rounded())

    let leftMargin = size * 0.180  // strata begin here

    ctx.setLineCap(.round)
    for stratum in strata {
        let y  = size * stratum.y
        let x0 = leftMargin
        let x1 = leftMargin + size * strataWidth
        let w  = stratum.isAccent ? strokeAccent : strokeBase
        let color: NSColor = stratum.isAccent
            ? cinnabar
            : sumi.withAlphaComponent(stratum.alpha)

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(w)
        ctx.move(to: CGPoint(x: x0, y: y))
        ctx.addLine(to: CGPoint(x: x1, y: y))
        ctx.strokePath()

        // Cinnabar coordinate-tick in the inner left margin — the
        // single graphic flourish, the astronomer's "I was watching
        // here" mark. Sized to read as a deliberate stroke even at
        // 64×64; collapses gracefully at smaller sizes.
        if stratum.isAccent {
            let tickX = size * 0.108
            let tickH = size * 0.030
            ctx.setStrokeColor(cinnabar.cgColor)
            ctx.setLineWidth(strokeAccent)
            ctx.move(to: CGPoint(x: tickX, y: y - tickH/2))
            ctx.addLine(to: CGPoint(x: tickX, y: y + tickH/2))
            ctx.strokePath()
        }
    }

    return image
}

// MARK: - Encoding

func writePNG(_ image: NSImage, size: CGFloat, to url: URL) throws {
    let target = NSSize(width: size, height: size)
    let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bmp.size = target
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
    image.draw(
        in: NSRect(origin: .zero, size: target),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bmp.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try png.write(to: url)
}

// MARK: - Main

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot  = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let appiconset = repoRoot
    .appendingPathComponent("QuickPad/Resources/Assets.xcassets/AppIcon.appiconset")

guard FileManager.default.fileExists(atPath: appiconset.path) else {
    FileHandle.standardError.write(
        Data("error: \(appiconset.path) not found — run from repo root\n".utf8)
    )
    exit(1)
}

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes {
    let image = renderIcon(size: s)
    let url = appiconset.appendingPathComponent("AppIcon-\(Int(s)).png")
    try writePNG(image, size: s, to: url)
    print("✓ \(url.lastPathComponent) (\(Int(s))×\(Int(s)))")
}

let contentsJSON = """
{
  "images" : [
    {
      "filename" : "AppIcon-16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "AppIcon-32.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "AppIcon-32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "AppIcon-64.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "AppIcon-128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "AppIcon-256.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "AppIcon-256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "AppIcon-512.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "AppIcon-512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contentsJSON.write(
    to: appiconset.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)
print("✓ Contents.json")
print("→ run scripts/release.sh --skip-tests to repackage")
