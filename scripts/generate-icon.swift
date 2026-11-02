import AppKit

// Draw the app's icon from simple vector paths. No external image assets.
let outputs = [(120, "AppIcon60@2x.png"), (180, "AppIcon60@3x.png"), (1024, "AppIcon1024.png")]
try FileManager.default.createDirectory(atPath: "Offload/Resources", withIntermediateDirectories: true)
for (size, filename) in outputs {
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
NSColor(red: 0.055, green: 0.075, blue: 0.07, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let drive = NSBezierPath(roundedRect: NSRect(x: 205, y: 245, width: 614, height: 255), xRadius: 65, yRadius: 65)
drive.lineWidth = 48
NSColor(red: 0.95, green: 0.94, blue: 0.90, alpha: 1).setStroke()
drive.stroke()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 512, y: 790)); arrow.line(to: NSPoint(x: 512, y: 415))
arrow.move(to: NSPoint(x: 380, y: 550)); arrow.line(to: NSPoint(x: 512, y: 415)); arrow.line(to: NSPoint(x: 644, y: 550))
arrow.lineWidth = 55; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(red: 0.30, green: 0.87, blue: 0.53, alpha: 1).setStroke(); arrow.stroke()
NSColor(red: 0.95, green: 0.94, blue: 0.90, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 690, y: 337, width: 44, height: 44)).fill()
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: "Offload/Resources/" + filename))
}
