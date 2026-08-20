//
//  RequirementsWidget.swift
//  Procyon
//
//  Created by Italo Mandara on 28/02/2026.
//

import SwiftUI

struct RequirementsWidget: View {
    let requirements: Requirements?

    private var minimumText: String {
        SteamTextFormatter.requirementText(fromHTML: requirements?.minimum ?? "")
    }

    private var recommendedText: String {
        SteamTextFormatter.requirementText(fromHTML: requirements?.recommended ?? "")
    }
    
    var body: some View {
        VStack (alignment: .leading) {
            HStack (alignment: .top) {
                Text(L10n.string("Minimum:")).frame(width: 100, alignment: .topLeading)
                Text(minimumText)
            }.padding(.bottom, 5)
            if !recommendedText.isEmpty {
                Divider()
                HStack (alignment: .top) {
                    Text(L10n.string("Recommended:")).frame(width: 100, alignment: .topLeading)
                    Text(recommendedText).padding(.bottom)
                }.padding(.top, 5)
            }
        }
        .padding()
        .background(.white.opacity(0.05))
        .cornerRadius(10)
    }
}

#Preview {
    RequirementsWidget(requirements: nil)
}
