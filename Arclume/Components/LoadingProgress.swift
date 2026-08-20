//
//  LoadingProgress.swift
//  Procyon
//
//  Created by Italo Mandara on 07/04/2026.
//

import SwiftUI

struct LoadingProgress: View {
    @Binding var progress: Double
    var body: some View {
        HStack(alignment: .center) {
            Image(.arclume).resizable()
                .scaledToFit()
                .frame(height: 50)
            VStack (alignment: .leading){
                Text(L10n.string("Loading your library…"))
                    .font(.footnote)
                    .foregroundStyle(.white)
                ProgressView(value: progress, total: 100)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity, maxHeight: 5)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 60)
        .background(.arclumeAccent.mix(with: .black, by: 0.6).opacity(0.9))
        .cornerRadius(20)
    }
}

#Preview {
    @Previewable @State var progress: Double = 0.0
    LoadingProgress(progress: $progress)
}
