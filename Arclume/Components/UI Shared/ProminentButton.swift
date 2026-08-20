//
//  ProminentButton.swift
//  Procyon
//
//  Created by Italo Mandara on 21/03/2026.
//

import SwiftUI

struct ProminentButton : View {
    var action: () -> Void
    var text: String
    var systemImage: String?
    var image: String?
    var isLoading: Bool
    
    init(
        _ text: String,
        systemImage: String? = nil,
        image: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.systemImage = systemImage
        self.image = image
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action()
        }) {
            ZStack {
                label.opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(text, systemImage: systemImage)
        } else if let image {
            HStack {
                Image(image).resizable().scaledToFit().frame(height: 20)
                Text(text)
            }
        } else {
            Text(text)
        }
    }
}

#Preview {
    ProminentButton("Hello") {
        print("Hello!")
    }
}
