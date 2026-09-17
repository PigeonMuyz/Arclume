import SwiftUI
import AppKit

/// LibraryPage is not inside a NavigationStack, so navigationTitle alone does not update NSWindow.
struct LibraryWindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleView { TitleView() }

    func updateNSView(_ view: TitleView, context: Context) {
        view.title = title
        view.updateTitle()
    }

    final class TitleView: NSView {
        var title = "Arclume"
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateTitle()
        }

        func updateTitle() {
            // SwiftUI may also write its scene title in the current update cycle.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, window.title != self.title else { return }
                window.title = self.title
            }
        }
    }
}
