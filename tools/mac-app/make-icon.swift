// Draws the app icon (1024 px PNG) following the macOS icon grid: a rounded square
// with a soft gradient and a white stack-of-photos symbol. Usage: swift make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [NSColor(srgbRed: 1.00, green: 0.62, blue: 0.24, alpha: 1),
                                   NSColor(srgbRed: 0.93, green: 0.30, blue: 0.47, alpha: 1),
                                   NSColor(srgbRed: 0.36, green: 0.33, blue: 0.93, alpha: 1)],
                          atLocations: [0, 0.52, 1], colorSpace: .sRGB)!
gradient.draw(in: shape, angle: -60)

let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "photo.stack.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = sym.size
    let r = NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - 8, width: s.width, height: s.height)
    sym.draw(in: r)
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
