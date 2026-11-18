import AppKit
import SwiftUI

struct ArclumeResetView: View {
    @State private var showConfirmation = false
    @State private var confirmation = ""
    @State private var resetAfterDismiss = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("重置 Arclume").font(.headline)
            Text("清除设置，并将容器内的游戏、存档和登录数据移到废纸篓。")
                .font(.footnote).foregroundStyle(.orange)
            Button("重置设置和应用数据…", role: .destructive) {
                confirmation = ""
                showConfirmation = true
            }
            .disabled(ArclumeTestEnvironment.isTesting)
        }
        .sheet(isPresented: $showConfirmation, onDismiss: {
            guard resetAfterDismiss else { return }
            resetAfterDismiss = false
            ArclumeResetCoordinator.shared.start()
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("确认重置设置与应用数据？").font(.title2)
                Text("请先保存所有 Windows 程序的工作。确认后会检查后台任务、结束 Arclume Wine 进程，并显示重置进度；完成后由你确认退出。")
                Text("Arclume 容器内的游戏、程序、存档与登录数据将随整个目录移到废纸篓；应用设置将清除。旧版本设置不会再次导入。")
                    .foregroundStyle(.orange)
                Text(ARCLUME_SUPPORT_FOLDER_URL.path).font(.caption).textSelection(.enabled)
                TextField("输入“重置”以确认", text: $confirmation)
                HStack {
                    Button("取消", role: .cancel) { showConfirmation = false }
                    Spacer()
                    Button("确认重置并退出", role: .destructive) {
                        resetAfterDismiss = true
                        showConfirmation = false
                    }.disabled(confirmation != "重置")
                }
            }.padding(24).frame(width: 480)
        }
    }
}
