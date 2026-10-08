import AppKit
import SwiftUI

struct ContainerManagementView: View {
    @StateObject private var store = ManagedWineContainerStore()
    @ObservedObject private var resources = DownloadableResourceStore.shared
    @State private var name = ""
    @State private var provider = WineRuntimeProvider.selected
    @State private var showsCreate = false
    @State private var renaming: ManagedWineContainer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Windows 容器").font(.headline)
                Spacer()
                Button("新建容器", systemImage: "plus") { name = ""; showsCreate = true }
                    .disabled(store.preparingID != nil || store.error != nil)
                    .accessibilityIdentifier("container-create")
            }
            ForEach(store.containers) { item in
                containerRow(item)
                if item.id != store.containers.last?.id { Divider() }
            }
            if let message = store.message {
                ProgressView(value: store.progress) { Text(message).font(.footnote) }
            }
            if let error = store.error {
                Text(error).font(.footnote).foregroundStyle(.red)
                Button("重新读取") { store.refresh() }.disabled(store.preparingID != nil)
            }
            Label("游戏指定容器暂未开放", systemImage: "lock")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear { store.refresh() }
        .popover(isPresented: $showsCreate) {
            VStack(alignment: .leading, spacing: 16) {
                Text("新建容器").font(.headline)
                TextField("容器名称", text: $name).textFieldStyle(.roundedBorder)
                Picker("运行时", selection: $provider) {
                    ForEach(WineRuntimeProvider.allCases) { Text($0.title).tag($0) }
                }
                Text("创建后可单独初始化，不会迁移现有游戏。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red) }
                HStack {
                    Button("取消") { showsCreate = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("创建") {
                        if store.create(name: name, provider: provider) { showsCreate = false }
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 320)
        }
        .alert("重命名容器", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("容器名称", text: $name)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let item = renaming { _ = store.rename(id: item.id, name: name) }
                renaming = nil
            }
        }
    }

    private func containerRow(_ item: ManagedWineContainer) -> some View {
        let prefix = item.prefixURL(root: store.repository.root)
        let ready = BundledWineRuntime.isValidPrefix(at: prefix)
        let exists = FileManager.default.fileExists(atPath: prefix.path)
        return HStack(spacing: 12) {
            Image(systemName: "shippingbox").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.subheadline.weight(.semibold))
                Text("\(item.provider.title) · \(ready ? "已就绪" : exists ? "需要检查" : "尚未初始化")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if !item.isDefault && !exists {
                Button("初始化") { Task { await store.initialize(id: item.id) } }
                    .disabled(store.preparingID != nil || resources.isBusy || resources.isSwitchingRuntime)
            }
            Menu {
                Button("打开容器目录") { NSWorkspace.shared.open(prefix) }.disabled(!exists)
                if !item.isDefault {
                    Button("重命名") { name = item.name; renaming = item }
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(store.preparingID != nil)
                .accessibilityLabel("\(item.name)的操作")
        }.accessibilityIdentifier("container-row-\(item.id)")
    }
}
