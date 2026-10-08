import AppKit
import Testing
@testable import Arclume

@MainActor
struct LauncherIconPresentationTests {
    private func icon(content: CGRect?) throws -> NSImage {
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if let content {
            context.setFillColor(NSColor.red.cgColor)
            context.fill(content)
        }
        return NSImage(cgImage: try #require(context.makeImage()), size: NSSize(width: 64, height: 64))
    }

    @Test func removesTransparentPaddingWithoutChangingOriginal() throws {
        let original = try icon(content: CGRect(x: 16, y: 16, width: 32, height: 32))
        let output = LauncherIconPresentation.normalized(original)
        #expect(output.size.width == 32)
        #expect(output.size.height == 32)
        #expect(original.size.width == 64)
    }

    @Test func preservesVisibleAspectRatio() throws {
        let output = LauncherIconPresentation.normalized(try icon(content: CGRect(x: 16, y: 8, width: 32, height: 48)))
        #expect(output.size.width == 32)
        #expect(output.size.height == 48)
    }

    @Test func transparentAndOpaqueIconsRemainUsable() throws {
        let transparent = try icon(content: nil)
        #expect(LauncherIconPresentation.normalized(transparent) === transparent)
        let opaque = try icon(content: CGRect(x: 0, y: 0, width: 64, height: 64))
        #expect(LauncherIconPresentation.normalized(opaque).size == opaque.size)
    }
}
