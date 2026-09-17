import SwiftUI

/// Window-filling first-run tour. Its illustrations never launch or install software.
struct LibraryWelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var configureSteam = false
    @State private var configureJX3 = false
    let onFinish: (Bool, Bool) -> Void

    private let titles = ["欢迎使用 Arclume", "从你的第一个应用开始", "游戏，都在这里", "按你的习惯出发"]
    private let descriptions = [
        "",
        "左下角的「操作」可以展开。安装 Windows 程序，或添加已有游戏，都从这里开始。",
        "用顶部搜索快速找到应用，在「已安装」和「全部」之间切换。Steam 的多个游戏库也会自动扫描。",
        "右上角的设置可以切换网格与启动器样式，也能管理运行环境和游戏库。"
    ]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("跳过引导") { onFinish(false, false) }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("welcome-skip")
                }
                .padding(.horizontal, 36).padding(.top, 22)

                ScrollView {
                    VStack(spacing: 26) {
                        if step == 0 {
                            brandMark
                                .frame(width: 210, height: 210)
                                .padding(.bottom, 6)
                        } else {
                            WelcomeLibraryIllustration(step: step)
                                .frame(maxWidth: 600).frame(height: 245)
                                .padding(.bottom, 6)
                        }
                        VStack(spacing: 14) {
                            Text(titles[step])
                                .font(.system(size: geometry.size.width < 700 ? 30 : 40, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            if step > 0 {
                                Text(descriptions[step])
                                    .font(.title3).foregroundStyle(.secondary)
                                    .lineSpacing(5).frame(maxWidth: 510)
                            }
                        }
                        .multilineTextAlignment(.center)
                        if step == 3 {
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle("配置Steam（可选）", isOn: $configureSteam)
                                    .accessibilityIdentifier("welcome-configure-steam")
                                Toggle("配置剑网3启动器（可选）", isOn: $configureJX3)
                                    .accessibilityIdentifier("welcome-configure-jx3")
                            }
                            .toggleStyle(.checkbox).fixedSize()
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(440, geometry.size.height - 150))
                }
                .scrollIndicators(.hidden)

                HStack {
                    Button("上一步") { advance(-1) }
                        .buttonStyle(.glass)
                        .disabled(step == 0)
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(0..<4) { index in
                            Capsule().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: index == step ? 24 : 7, height: 7)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("第 \(step + 1) 步，共 4 步")
                    Spacer()
                    Button(step == 0 ? "开始认识 Arclume" : step == 3 ? "开始使用" : "继续") {
                        if step == 3 { onFinish(configureSteam, configureJX3) }
                        else { advance(1) }
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("welcome-next")
                }
                .controlSize(.large)
                .padding(.horizontal, 36).padding(.vertical, 24)
            }
            .background {
                Rectangle().fill(.background)
                    .overlay {
                        RadialGradient(colors: [.accentColor.opacity(0.22), .clear],
                                       center: .init(x: 0.5, y: 0.3), startRadius: 20,
                                       endRadius: max(geometry.size.width, geometry.size.height) * 0.65)
                    }
                    .ignoresSafeArea()
            }
        }
        .accessibilityIdentifier("library-welcome")
    }

    private func advance(_ delta: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step += delta }
    }

    private var brandMark: some View {
        ZStack {
            Image("WelcomeIconBackground").resizable().scaledToFit()
            Image("WelcomeIconForeground").resizable().scaledToFit()
                .frame(width: 158, height: 145)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, lifted in
                    content.offset(y: lifted ? -5 : 3)
                } animation: { _ in .easeInOut(duration: 2.2) }
        }
        .accessibilityHidden(true)
    }
}

/// A small, inert map of the library: the arrow points to the same controls the user will see.
private struct WelcomeLibraryIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let step: Int

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Circle().fill(.secondary.opacity(0.3)).frame(width: 8, height: 8)
                    Text("Arclume").fontWeight(.semibold)
                    Spacer(minLength: 4)
                    Label("搜索 · 已安装 / 全部", systemImage: "magnifyingglass")
                        .font(.caption).padding(9)
                        .background(step == 2 ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08), in: Capsule())
                    Image(systemName: "gearshape").padding(9)
                        .background(step == 3 ? Color.accentColor.opacity(0.25) : Color.clear, in: Circle())
                }
                HStack(spacing: 14) {
                    previewCard("gamecontroller", title: "游戏")
                    previewCard("app.dashed", title: "应用")
                    previewCard("square.stack.3d.up", title: "游戏库")
                }
                HStack(spacing: 12) {
                    Label("操作", systemImage: "plus").font(.callout.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(step == 1 ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                    if step == 1 { Text("添加游戏 · 安装程序").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }
            }
            .padding(18)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.1))
            }
            Image(systemName: step == 1 ? "arrow.down" : "arrow.up")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, moved in
                    content.offset(y: moved ? (step == 1 ? 5 : -5) : 0)
                } animation: { _ in .easeInOut(duration: 0.7) }
                .position(x: step == 1 ? 60 : step == 2 ? geometry.size.width - 170 : geometry.size.width - 35,
                          y: step == 1 ? 166 : 79)
        }
        .accessibilityHidden(true)
    }

    private func previewCard(_ symbol: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 27, weight: .light))
            Text(title).font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity).frame(height: 100)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
