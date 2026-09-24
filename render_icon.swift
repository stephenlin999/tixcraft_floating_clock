import AppKit

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let sourceData = try Data(contentsOf: sourceURL)
guard let bitmap = NSBitmapImageRep(data: sourceData),
      let sourceImage = bitmap.cgImage else {
    fatalError("Cannot decode source icon")
}

// Measure the artwork, excluding the light background, before positioning it.
var left = bitmap.pixelsWide, right = 0
var top = bitmap.pixelsHigh, bottom = 0
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
              color.alphaComponent > 0.9 else { continue }
        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        if luminance < 0.65 {
            left = min(left, x); right = max(right, x)
            top = min(top, y); bottom = max(bottom, y)
        }
    }
}
precondition(right > left && bottom > top, "Source icon has no artwork")
let scale = 612.0 / CGFloat(right - left + 1)
let centerX = CGFloat(left + right + 1) / 2
let centerY = CGFloat(bitmap.pixelsHigh) - CGFloat(top + bottom + 1) / 2
let image = NSImage(cgImage: sourceImage, size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
NSBezierPath(ovalIn: NSRect(x: 100, y: 100, width: 824, height: 824)).addClip()
image.draw(in: NSRect(x: 512 - centerX * scale, y: 512 - centerY * scale,
    width: image.size.width * scale, height: image.size.height * scale))
NSGraphicsContext.restoreGraphicsState()
try output.representation(using: .png, properties: [:])!.write(to: outputURL)
print("Centered artwork from bounds \(left),\(top)-\(right),\(bottom) on a 1024px canvas")
