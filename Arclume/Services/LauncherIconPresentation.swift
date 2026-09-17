import AppKit

/// Normalize transparent padding at display time without rewriting the app's icon.
enum LauncherIconPresentation {
    static func normalized(_ image: NSImage) -> NSImage {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let original = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return image }
        let side = 256
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return image }
        // This raster is only for bounds measurement; interpolation would invent faint edge pixels.
        context.interpolationQuality = .none
        context.draw(original, in: CGRect(x: 0, y: 0, width: side, height: side))
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where pixels[(y * side + x) * 4 + 3] > 24 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        let sx = CGFloat(original.width) / CGFloat(side)
        let sy = CGFloat(original.height) / CGFloat(side)
        let bounds = CGRect(x: CGFloat(minX) * sx, y: CGFloat(minY) * sy,
                            width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy).integral
        guard let cropped = original.cropping(to: bounds) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}
