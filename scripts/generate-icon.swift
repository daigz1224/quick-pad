#!/usr/bin/env swift
//
// Generates QuickPad's AppIcon set procedurally — same design language
// as MenuBarIcon (rapid-log rows: bullet glyph + horizontal "text"
// lines) scaled up to a full macOS app icon. Colors match
// QuickPad/Views/ThemePreset.swift so menu-bar and app icon read as
// the same family.
//
// Usage:  swift scripts/generate-icon.swift
//
// Writes PNGs into QuickPad/Resources/Assets.xcassets/AppIcon.appiconset/
// at every size the asset catalog needs, and rewrites Contents.json so
// each slot's declared dimensions match its physical pixels.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Palette (mirrors QuickPad/Views/ThemePreset.swift Default palette)

let bgDark       = NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
let panelDark    = NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)
let textTertiary = NSColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1.0)
let accent       = NSColor(red: 0.40, green: 0.55, blue: 0.90, alpha: 1.0)
let taskDone     = NSColor(red: 0.30, green: 0.78, blue: 0.60, alpha: 1.0)
let idea         = NSColor(red: 0.95, green: 0.75, blue: 0.30, alpha: 1.0)

// MARK: - Renderer

func renderIcon(size: CGFloat) -> NSImage {
    let canvas = NSSize(width: size, height: size)
    let image = NSImage(size: canvas)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // Background squircle. macOS Big Sur+ icon corner ≈ 22.37% of width
    // — close enough to Apple's continuous-corner spec for the
    // pixel-accuracy we need.
    let cornerRadius = size * 0.2237
    let bgRect = CGRect(origin: .zero, size: canvas)
    let bgPath = CGPath(
        roundedRect: bgRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.addPath(bgPath); ctx.setFillColor(bgDark.cgColor); ctx.fillPath()

    // Subtle top-to-bottom gradient inside the squircle so the icon
    // doesn't read as a flat black rectangle at large sizes.
    ctx.saveGState()
    ctx.addPath(bgPath); ctx.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            panelDark.cgColor,
            bgDark.cgColor,
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size),
            end: .zero,
            options: []
        )
    }
    ctx.restoreGState()

    // Three stream rows — tighter spacing than the original sketch so
    // the content reads as a clean rapid-log block, not a sparse list.
    // Cocoa coords: origin is bottom-left, so the first entry in
    // `rowYs` is the visually-top row.
    let rowSpacing = size * 0.135
    let centerY    = size * 0.50
    let rowYs: [CGFloat] = [centerY + rowSpacing, centerY, centerY - rowSpacing]

    let bulletX     = size * 0.24
    let textStartX  = size * 0.36
    let glyphSize   = size * 0.062
    let lineHeight  = size * 0.024

    // Row 1 — note (accent dash) + 2 text lines.
    let r0 = rowYs[0]
    drawDash(
        in: ctx,
        center: CGPoint(x: bulletX, y: r0),
        length: glyphSize * 1.4,
        thickness: size * 0.022,
        color: accent
    )
    drawTextLine(
        in: ctx, start: CGPoint(x: textStartX, y: r0 + size * 0.016),
        length: size * 0.40, thickness: lineHeight, color: textTertiary
    )
    drawTextLine(
        in: ctx, start: CGPoint(x: textStartX, y: r0 - size * 0.032),
        length: size * 0.26, thickness: lineHeight,
        color: textTertiary.withAlphaComponent(0.55)
    )

    // Row 2 — task (green checkbox) + 1 text line.
    let r1 = rowYs[1]
    drawCheckbox(
        in: ctx,
        center: CGPoint(x: bulletX, y: r1),
        sideLength: glyphSize,
        thickness: size * 0.014,
        color: taskDone
    )
    drawTextLine(
        in: ctx, start: CGPoint(x: textStartX, y: r1),
        length: size * 0.32, thickness: lineHeight, color: textTertiary
    )

    // Row 3 — priority (yellow `!`) + 1 text line.
    let r2 = rowYs[2]
    drawExclamation(
        in: ctx,
        center: CGPoint(x: bulletX, y: r2),
        height: glyphSize * 1.2,
        thickness: size * 0.022,
        color: idea
    )
    drawTextLine(
        in: ctx, start: CGPoint(x: textStartX, y: r2),
        length: size * 0.36, thickness: lineHeight, color: textTertiary
    )

    return image
}

// MARK: - Glyph primitives

func drawDash(in ctx: CGContext, center: CGPoint, length: CGFloat, thickness: CGFloat, color: NSColor) {
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(thickness)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: center.x - length/2, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x + length/2, y: center.y))
    ctx.strokePath()
}

func drawCheckbox(in ctx: CGContext, center: CGPoint, sideLength: CGFloat, thickness: CGFloat, color: NSColor) {
    let rect = CGRect(
        x: center.x - sideLength/2,
        y: center.y - sideLength/2,
        width: sideLength,
        height: sideLength
    )
    let r = thickness * 1.2
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(thickness)
    ctx.strokePath()
}

func drawExclamation(in ctx: CGContext, center: CGPoint, height: CGFloat, thickness: CGFloat, color: NSColor) {
    ctx.setFillColor(color.cgColor)
    // Bar (upper ~60%).
    let barHeight = height * 0.62
    let bar = CGRect(
        x: center.x - thickness/2,
        y: center.y - height/2 + height * 0.32,
        width: thickness,
        height: barHeight
    )
    ctx.addPath(CGPath(
        roundedRect: bar,
        cornerWidth: thickness/2, cornerHeight: thickness/2,
        transform: nil
    ))
    ctx.fillPath()
    // Dot at bottom.
    let dot = thickness * 1.4
    let dotRect = CGRect(
        x: center.x - dot/2,
        y: center.y - height/2,
        width: dot, height: dot
    )
    ctx.fillEllipse(in: dotRect)
}

func drawTextLine(in ctx: CGContext, start: CGPoint, length: CGFloat, thickness: CGFloat, color: NSColor) {
    let rect = CGRect(
        x: start.x,
        y: start.y - thickness/2,
        width: length,
        height: thickness
    )
    ctx.setFillColor(color.cgColor)
    ctx.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: thickness/2, cornerHeight: thickness/2,
        transform: nil
    ))
    ctx.fillPath()
}

// MARK: - Encoding

func writePNG(_ image: NSImage, size: CGFloat, to url: URL) throws {
    // Force the bitmap to render at exactly `size × size` pixels —
    // NSImage.tiffRepresentation can otherwise embed @2x metadata that
    // makes actool warn about size mismatches.
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

// Rewrite Contents.json so every slot points to a PNG with the
// matching physical size — fixes the actool size warnings.
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
