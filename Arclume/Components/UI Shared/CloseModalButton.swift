//
//  CloseModalButton.swift
//  Procyon
//
//  Created by Italo Mandara on 07/02/2026.
//

import SwiftUI

struct CloseModalButton: View {
    @Binding var show: Bool
    
    var body: some View {
        Button {
            show = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass).controlSize(.large).buttonBorderShape(.circle)
        .keyboardShortcut(.cancelAction)
        .help("关闭").accessibilityLabel("关闭")
    }
}

#Preview {
    @State @Previewable var show = true
    CloseModalButton(show: $show)
}
