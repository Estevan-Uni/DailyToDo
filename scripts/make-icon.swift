import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Output PNG path required") }
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(srgbRed: 0.28, green: 0.49, blue: 0.43, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 220, yRadius: 220).fill()
for (index, y) in [690.0, 490.0, 290.0].enumerated() {
    let check = NSBezierPath(roundedRect: NSRect(x: 208, y: y, width: 94, height: 94), xRadius: 24, yRadius: 24)
    NSColor.white.withAlphaComponent(index == 0 ? 0.95 : 0.48).setStroke()
    check.lineWidth = 13
    check.stroke()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 370, y: y + 47)); line.line(to: NSPoint(x: 794, y: y + 47))
    line.lineWidth = 23; line.lineCapStyle = .round; line.stroke()
    if index == 0 {
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 225, y: y + 48)); mark.line(to: NSPoint(x: 248, y: y + 23)); mark.line(to: NSPoint(x: 289, y: y + 77))
        mark.lineWidth = 13; mark.lineCapStyle = .round; mark.lineJoinStyle = .round; mark.stroke()
    }
}
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon encoding failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
