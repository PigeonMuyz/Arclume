import AppKit
import Testing
@testable import Arclume

@MainActor struct LauncherTourRegistryTests {
    @Test func detachedReplacementDoesNotHideLiveButton() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let live = NSView(frame: CGRect(x: 400, y: 20, width: 300, height: 48))
        window.contentView?.addSubview(live)
        let detached = NSView(frame: live.frame)
        let registry = LauncherTourRegistry()
        registry.register(live, for: .play)
        registry.register(detached, for: .play)
        registry.update(in: window)
        #expect(registry.rectangles[.play]?.width == 300)
        live.removeFromSuperview()
        registry.update(in: window)
        #expect(registry.rectangles[.play] == nil)
    }

    @Test func onboardingDemoDoesNotLoadSavedLibraryOrAdoptPrefix() {
        let library = LibraryPageGlobals(loadSavedLibrary: false)
        let globals = AppGlobals(demonstrationOnly: true)
        #expect(library.games.isEmpty && library.customAddedGames.isEmpty)
        #expect(globals.selectedBottle.isEmpty)
        #expect(globals.cxAppPath == nil)
    }
}
