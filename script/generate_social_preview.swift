#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconURL = root.appendingPathComponent("Resources/AppIcon.png")
let screenshotURL = root.appendingPathComponent("docs/images/app-screenshot.png")
let outputURL = root.appendingPathComponent("docs/images/social-preview.png")

guard let icon = NSImage(contentsOf: iconURL) else {
    fatalError("Could not load \(iconURL.path)")
}

guard let screenshot = NSImage(contentsOf: screenshotURL) else {
    fatalError("Could not load \(screenshotURL.path)")
}

let canvasSize = NSSize(width: 1280, height: 640)
let image = NSImage(size: canvasSize)

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.969, blue: 0.957, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

NSColor(calibratedRed: 0.10, green: 0.60, blue: 0.30, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: canvasSize.height)).fill()

icon.draw(
    in: NSRect(x: 72, y: 468, width: 88, height: 88),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

let titleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 48, weight: .bold),
    .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1)
]
let subtitleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1)
]
let bodyStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 21, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.36, alpha: 1)
]
let footerStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.28, alpha: 1)
]

("Codex Login\nManager" as NSString).draw(
    in: NSRect(x: 72, y: 320, width: 470, height: 130),
    withAttributes: titleStyle
)
("Diagnose Codex CLI login on macOS" as NSString).draw(
    in: NSRect(x: 72, y: 258, width: 470, height: 44),
    withAttributes: subtitleStyle
)
("ChatGPT OAuth  ·  API key mode\nLocal-only  ·  Open source" as NSString).draw(
    in: NSRect(x: 72, y: 174, width: 470, height: 62),
    withAttributes: bodyStyle
)
("github.com/xiaohei210509/CodexLoginManager" as NSString).draw(
    in: NSRect(x: 72, y: 88, width: 480, height: 30),
    withAttributes: footerStyle
)

let screenshotRect = NSRect(x: 588, y: 62, width: 640, height: 496)
NSColor(calibratedWhite: 0, alpha: 0.14).setFill()
NSBezierPath(
    roundedRect: screenshotRect.offsetBy(dx: 0, dy: -10),
    xRadius: 8,
    yRadius: 8
).fill()

NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: screenshotRect, xRadius: 8, yRadius: 8).addClip()
screenshot.draw(
    in: screenshotRect,
    from: NSRect(origin: .zero, size: screenshot.size),
    operation: .sourceOver,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the social preview")
}

try png.write(to: outputURL, options: .atomic)

let resize = Process()
resize.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
resize.arguments = ["-z", "640", "1280", outputURL.path]
resize.standardOutput = FileHandle.nullDevice
resize.standardError = FileHandle.nullDevice
try resize.run()
resize.waitUntilExit()

guard resize.terminationStatus == 0 else {
    fatalError("Could not resize the social preview to 1280x640")
}

print("Generated \(outputURL.path)")
