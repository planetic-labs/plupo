import AppKit

// Finder positions use points. Keep matching 1x and Retina representations.
let width: CGFloat = 600
let height: CGFloat = 380
let image = NSImage(size: NSSize(width: width, height: height))
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
                              pixelsHigh: Int(height) * scale, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(colors: [NSColor(srgbRed: 0.998, green: 0.995, blue: 1, alpha: 1),
                        NSColor(srgbRed: 0.96, green: 0.95, blue: 0.98, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -70)

    let ink = NSColor(srgbRed: 0.17, green: 0.15, blue: 0.22, alpha: 1)
    let secondary = NSColor(srgbRed: 0.48, green: 0.46, blue: 0.53, alpha: 1)
    func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat,
              weight: NSFont.Weight, color: NSColor, centered: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        (value as NSString).draw(in: NSRect(x: x, y: height - top - size * 1.5,
                                           width: width - x * 2, height: size * 1.6),
            withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                             .foregroundColor: color, .paragraphStyle: style])
    }
    text("Plupo", x: 42, top: 27, size: 28, weight: .semibold, color: ink)
    text("Drag. Drop. Keep moving.", x: 43, top: 70, size: 13, weight: .regular, color: secondary)

    // The only graphic between the two real, draggable Finder icons.
    let arrow = NSBezierPath()
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let y = height - 197
    arrow.move(to: NSPoint(x: 273, y: y))
    arrow.line(to: NSPoint(x: 327, y: y))
    arrow.move(to: NSPoint(x: 318, y: y + 9))
    arrow.line(to: NSPoint(x: 327, y: y))
    arrow.line(to: NSPoint(x: 318, y: y - 9))
    NSColor(srgbRed: 0.65, green: 0.59, blue: 0.76, alpha: 1).setStroke()
    arrow.stroke()

    text("Drag Plupo into Applications", x: 30, top: 297, size: 14,
         weight: .medium, color: ink, centered: true)
    text("Apple Silicon + Intel  ·  macOS 14.0 or later", x: 30, top: 332, size: 11,
         weight: .regular, color: secondary, centered: true)
    NSGraphicsContext.restoreGraphicsState()
    rep.setCompression(.lzw, factor: 1)
    image.addRepresentation(rep)
}
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "scripts/dmg/background.tiff"
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: output))
