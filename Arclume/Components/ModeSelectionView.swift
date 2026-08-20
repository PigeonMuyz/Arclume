//
//  ModeSelectionView.swift
//  Procyon
//

import SwiftUI
import AppKit

struct ModeSelectionView: View {
    let allowsCancel: Bool
    let onSelect: (ArclumeMode) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        allowsCancel: Bool = false,
        onSelect: @escaping (ArclumeMode) -> Void
    ) {
        self.allowsCancel = allowsCancel
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text(allowsCancel ? "选择运行模式" : "欢迎使用 Arclume")
                        .font(.largeTitle.weight(.bold))

                    Text("选择后，Arclume 会按对应模式扫描和管理游戏。")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 18),
                        GridItem(.flexible(), spacing: 18)
                    ],
                    spacing: 18
                ) {
                    ForEach(ArclumeMode.allCases) { mode in
                        ModeSelectionCard(mode: mode) {
                            onSelect(mode)
                            if allowsCancel {
                                dismiss()
                            }
                        }
                    }
                }
                .frame(maxWidth: 760)

                Text(
                    allowsCancel
                        ? "你可以稍后在设置中切换模式。"
                        : "这个选择会保存在本机，之后打开 Arclume 将直接进入所选模式。"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 42)
        }
        .accessibilityIdentifier("mode-selection-view")
    }
}

private struct ModeSelectionCard: View {
    let mode: ArclumeMode
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.arclumeSecondary)
                        .frame(width: 52, height: 52)
                        .background(.arclumeSecondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))

                    Text(mode.title)
                        .font(.title2.weight(.bold))

                    Text(mode == .standard
                         ? "会读取Steam游戏库，不支持识别剑网3"
                         : "只支持识别剑网3")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(isHovering ? 0.92 : 0.42))
            }
            .padding(24)
            .background(
                .regularMaterial.opacity(isHovering ? 0.96 : 0.82),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isHovering
                            ? Color.arclumeSecondary.opacity(0.9)
                            : Color.white.opacity(0.16),
                        lineWidth: isHovering ? 2 : 1
                    )
            }
            .shadow(
                color: .black.opacity(isHovering ? 0.3 : 0.16),
                radius: isHovering ? 18 : 10,
                y: isHovering ? 8 : 4
            )
            .scaleEffect(isHovering ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mode-card-\(mode.rawValue)")
        .onContinuousHover { phase in
            let hovering: Bool
            switch phase {
            case .active:
                hovering = true
            case .ended:
                hovering = false
            }
            guard isHovering != hovering else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    ModeSelectionView { _ in }
        .frame(width: 1024, height: 750)
        .preferredColorScheme(.dark)
}
