import SwiftUI

struct LauncherTourOverlay: View {
    @ObservedObject var registry: LauncherTourRegistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var choosingSetup = false
    @State private var configureSteam = false
    @State private var configureJX3 = false
    let onFinish: (Bool, Bool) -> Void
    var offersSetup = true
    var startsAtSetup = false
    private let targets: [LauncherTourTarget?] = [nil, .add, .sidebar, .allGames, .collapse, .play, .more, .settings]
    private let titles = ["欢迎使用 Arclume", "添加游戏与应用", "切换游戏", "你的全部游戏", "收起游戏列表", "开始游戏", "管理当前项目", "按你的习惯出发"]
    private let details = ["接下来直接在界面上认识常用功能。没有游戏时展示的是演示项目，不会保存或启动。",
        "使用这里的 ＋ 添加本机应用、Windows 程序或安装包。",
        "点击图标切换当前游戏；按住图标拖动可以调整顺序，悬停可查看名称。",
        "这里可以查看和搜索所有已安装的项目。选中只切换展示，不会直接启动。",
        "底部箭头用于收起或展开左侧游戏列表，让背景有更多展示空间。",
        "选择游戏后从这里启动。引导期间不会实际启动游戏。",
        "更多菜单包含安装目录、运行设置和项目信息；剑网3还提供画质设置。",
        "设置里可以管理游戏库、运行环境及外观。完成教学后，可以按需配置启动器。"]

    var body: some View {
        GeometryReader { geometry in
            let target = targets[step].flatMap { registry.rectangles[$0] }
            let hole = target?.insetBy(dx: -7, dy: -7)
            let size = geometry.size
            let cardWidth = min(360.0, max(240.0, size.width - 48))
            let right = (target?.midX ?? size.width) < size.width / 2
            let cardCenter = LauncherTourLayout.cardCenter(in: size, target: target, cardWidth: cardWidth)
            ZStack {
                if choosingSetup {
                    setupChoice
                } else if step == 0 {
                    OnboardingStage(title: "欢迎使用 Arclume", showsBrand: true) {
                        EmptyView()
                    } actions: {
                        Button("跳过教学") { finishTeaching() }.buttonStyle(.glass)
                        Spacer()
                        Button("开始认识 Arclume") { advance(1) }
                            .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    }
                } else {
                TourMask(hole: hole ?? .zero)
                    .fill(LinearGradient(colors: [.indigo.opacity(0.62), .accentColor.opacity(0.38), .black.opacity(0.48)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), style: FillStyle(eoFill: true))
                // Capture clicks even in the cutout: demonstration must not launch apps.
                Color.clear.contentShape(Rectangle())
                if let hole {
                    RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.9), lineWidth: 2)
                        .frame(width: hole.width, height: hole.height).position(x: hole.midX, y: hole.midY)
                        .shadow(color: .accentColor.opacity(0.8), radius: 12)
                    Image(systemName: right ? "arrow.left" : "arrow.right")
                        .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                        .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, moved in
                            content.offset(x: moved ? (right ? -6 : 6) : 0)
                        } animation: { _ in .easeInOut(duration: 0.7) }
                        .position(x: right ? hole.maxX + 28 : hole.minX - 28, y: hole.midY)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("\(step) / \(targets.count - 1)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("跳过教学") { finishTeaching() }.buttonStyle(.borderless)
                            .keyboardShortcut(.cancelAction)
                    }
                    Text(titles[step]).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(details[step]).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("上一步") { advance(-1) }.disabled(step <= 1).buttonStyle(.glass)
                        Spacer()
                        Button(step == targets.count - 1 ? "完成教学" : "下一步") {
                            if step == targets.count - 1 { finishTeaching() }
                            else { advance(1) }
                        }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    }.padding(.top, 4)
                }
                .padding(24).frame(width: cardWidth)
                .background(.regularMaterial, in: .rect(cornerRadius: 22))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 6)
                .position(cardCenter)
                }
            }.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("launcher-live-tour")
        .onAppear { choosingSetup = startsAtSetup }
    }
    private func finishTeaching() {
        if offersSetup { choosingSetup = true }
        else { onFinish(false, false) }
    }
    private var setupChoice: some View {
        OnboardingStage(title: "准备开始", showsBrand: true) {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("配置Steam（可选）", isOn: $configureSteam)
                Toggle("配置剑网3启动器（可选）", isOn: $configureJX3)
            }.toggleStyle(.checkbox).fixedSize()
        } actions: {
            Button("返回教学") { choosingSetup = false; step = 1 }.buttonStyle(.glass)
            Spacer()
            Button(configureSteam || configureJX3 ? "继续配置" : "开始使用") {
                onFinish(configureSteam, configureJX3)
            }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
        }
    }
    private func advance(_ delta: Int) { step = max(1, min(targets.count - 1, step + delta)) }
}

private struct TourMask: Shape {
    var hole: CGRect
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(hole.minX, hole.minY), .init(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if !hole.isEmpty { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16)) }
        return path
    }
}
