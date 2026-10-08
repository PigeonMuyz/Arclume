import AppKit
import SwiftUI

enum LauncherAccent {
    /// Favor saturated pixels; transparent margins, white glyphs and black outlines
    /// must not dominate the icon's color. Rasterization is bounded to 32x32.
    static func color(from image: NSImage) -> Color {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return .accentColor }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let pixels = data.bindMemory(to: UInt8.self, capacity: 4096)
        var buckets = [(weight: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        for index in stride(from: 0, to: 4096, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[index]) / 255 / alpha
            let g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            let saturation = color.saturationComponent
            guard saturation > 0.22, color.brightnessComponent > 0.18 else { continue }
            let bucket = min(11, Int(color.hueComponent * 12))
            let weight = saturation * alpha
            buckets[bucket].weight += weight
            buckets[bucket].r += r * weight; buckets[bucket].g += g * weight; buckets[bucket].b += b * weight
        }
        guard let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > 0 else { return .accentColor }
        let source = NSColor(srgbRed: best.r / best.weight, green: best.g / best.weight, blue: best.b / best.weight, alpha: 1)
        let adjusted = NSColor(calibratedHue: source.hueComponent,
            saturation: min(0.8, source.saturationComponent), brightness: source.brightnessComponent, alpha: 1)
            .usingColorSpace(.sRGB) ?? source
        let scale = min(1, 0.65 / max(adjusted.redComponent, adjusted.greenComponent, adjusted.blueComponent))
        return Color(.sRGB, red: adjusted.redComponent * scale,
                     green: adjusted.greenComponent * scale, blue: adjusted.blueComponent * scale)
    }
}
