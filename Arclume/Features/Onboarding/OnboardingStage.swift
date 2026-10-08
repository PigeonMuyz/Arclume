import SwiftUI

/// One window-filling visual language for welcome, upgrade and optional setup.
struct OnboardingStage<Content: View, Actions: View>: View {
    let title: String
    var showsBrand = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {
                        if showsBrand { OnboardingBrandMark().frame(width: 200, height: 200) }
                        Text(title).font(.system(size: 36, weight: .semibold))
                            .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        content()
                    }
                    .frame(maxWidth: 680)
                    .padding(40)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(350, geometry.size.height - 110))
                }
                .scrollIndicators(.hidden)
                HStack { actions() }
                    .controlSize(.large).padding(.horizontal, 40).padding(.vertical, 28)
            }
            .background {
                Rectangle().fill(.background)
                    .overlay {
                        RadialGradient(colors: [.accentColor.opacity(0.22), .clear],
                            center: .init(x: 0.5, y: 0.3), startRadius: 20,
                            endRadius: max(geometry.size.width, geometry.size.height) * 0.65)
                    }.ignoresSafeArea()
            }
        }
    }
}

struct OnboardingBrandMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Image("WelcomeIconBackground").resizable().scaledToFit()
            Image("WelcomeIconForeground").resizable().scaledToFit()
                .frame(width: 150, height: 138)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, lifted in
                    content.offset(y: lifted ? -5 : 3)
                } animation: { _ in .easeInOut(duration: 2.2) }
        }.accessibilityHidden(true)
    }
}
