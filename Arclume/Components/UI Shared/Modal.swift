//
//  Modal.swift
//  Procyon
//
//  Created by Italo Mandara on 01/02/2026.
//

import SwiftUI

struct Modal<Content: View>: View {
    @Binding var showModal: Bool
    var title: String? = nil
    var collapse: Bool? = false
    var scrollable: Bool? = true
    var allowsClose = true
    var subdued = false
    let content: Content
    
    init(
        _ title: String? = nil,
        showModal: Binding<Bool>,
        collapse: Bool? = nil,
        scrollable: Bool = true,
        allowsClose: Bool = true,
        subdued: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self._showModal = showModal
        self.title = title
        self.collapse = collapse
        self.content = content()
        self.scrollable = scrollable
        self.allowsClose = allowsClose
        self.subdued = subdued
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let title { Text(title).font(.headline).lineLimit(1) }
                Spacer(minLength: 16)
                if allowsClose { CloseModalButton(show: $showModal) }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            if(scrollable == true) {
                ScrollView(.vertical) {
                    content
                        .padding(collapse == true ? 0 : 24)
                }
            } else {
                content
                    .padding(collapse == true ? 0 : 20)
            }
        }
        .background(.regularMaterial)
    }
}
