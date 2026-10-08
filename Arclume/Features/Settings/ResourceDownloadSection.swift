import SwiftUI

struct ResourceDownloadSection: View {
    @ObservedObject var store: DownloadableResourceStore
    var showsAction = true
    var purpose: DownloadableResourceCatalog.Purpose = .runtime
    @State private var pendingIDs: Set<String> = []
    @State private var confirmsDownload = false
    @State private var confirmationIsPreparation = false
    @State private var activationError: String?

    init(store: DownloadableResourceStore = .shared, showsAction: Bool = true,
         purpose: DownloadableResourceCatalog.Purpose = .runtime) {
        self.store = store
        self.showsAction = showsAction
        self.purpose = purpose
    }

    var body: some View {
        let required = store.requiredIDs(for: purpose)
        let status = store.status(for: purpose)
        VStack(alignment: .leading, spacing: 14) {
            RuntimeProviderPicker(store: store)
            ForEach(store.components.filter { required.contains($0.id) && $0.type != "runtime" }, id: \.id) { item in
                componentRow(item)
            }
            DisclosureGroup("其他组件（按需下载）") {
                VStack(spacing: 14) {
                    ForEach(store.components.filter { !required.contains($0.id) }, id: \.id) { item in
                        componentRow(item)
                    }
                }.padding(.top, 12)
            }
            if store.isBusy {
                ProgressView(value: store.progress) {
                    Text(store.message ?? "正在下载所选组件…").font(.footnote)
                }
                if let detail = store.transferDetail {
                    Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            } else if showsAction && !status.isReady {
                Button(store.selectedProvider == .nefinita ? store.preparationTitle : purpose == .runtime ? status.actionTitle : "补全初始化所需组件") {
                    pendingIDs = required
                    confirmationIsPreparation = true
                    confirmsDownload = true
                }.buttonStyle(.bordered)
            } else if showsAction && store.selectedProvider != store.activeProvider {
                Button("使用 \(store.selectedProvider.title)") {
                    Task {
                        do { try await store.activateSelection(); activationError = nil }
                        catch { activationError = error.localizedDescription }
                    }
                }.buttonStyle(.bordered)
            }
            if let activationError { Text(activationError).font(.footnote).foregroundStyle(.red) }
            if let error = store.error {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(store.isSwitchingRuntime)
        .alert(confirmationIsPreparation && store.selectedProvider == .nefinita ? "准备 Nefinita？" : "下载所选组件？", isPresented: $confirmsDownload) {
            Button("取消", role: .cancel) {}
            Button(confirmationIsPreparation && store.selectedProvider == .nefinita ? "开始准备" : "开始下载") {
                let ids = pendingIDs
                let prepare = confirmationIsPreparation
                Task { try? await store.download(purpose: purpose, componentIDs: prepare ? nil : ids) }
            }
        } message: {
            Text(store.confirmationMessage(purpose: purpose, componentIDs: confirmationIsPreparation ? nil : pendingIDs))
        }
        .onAppear { store.refresh() }
    }

    private func componentRow(_ item: DownloadableResourceCatalog.Component) -> some View {
        let ready = store.componentReady(item)
        return HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(ready ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.subheadline.weight(.semibold))
                Text(item.type == "runtime" ? store.status.runtimeDetail :
                     "\(item.version) · \(ready ? "已下载" : ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if !ready {
                Button(store.isBusy && store.requestedIDs.contains(item.id) ? "处理中…" : "下载") {
                    pendingIDs = [item.id]
                    confirmationIsPreparation = false
                    confirmsDownload = true
                }.buttonStyle(.bordered).disabled(store.isBusy)
            }
        }
    }
}
