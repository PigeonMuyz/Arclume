//
//  PlayButtonExtras.swift
//  Procyon
//
//  Created by Italo Mandara on 06/03/2026.
//

import SwiftUI

struct PlayButtonExtras: View {
    var playAction: () -> Void
    var stopAction: () -> Void
    var optionsAction: (() -> Void)?
    var editAction: (() -> Void)?
    var folderAction: () -> Void
    var isPlaying: Bool
    
    var body: some View {
        HStack{
            Button { isPlaying ? stopAction() : playAction() } label: {
                Label(
                    isPlaying ? L10n.string("Stop") : L10n.string("Play"),
                    systemImage: "play.fill"
                )
                    .padding(.vertical, 10)
                    .padding(.leading, 20)
            }.font(.system(size: 16))
            if let optionsAction {
                Divider()
                Button { optionsAction() } label: {
                    Image(systemName: "gear")
                        .padding(.vertical, 10)
                }
            }
            if let editAction {
                Divider()
                Button { editAction() } label: {
                    Image(systemName: "pencil")
                        .padding(.vertical, 10)
                }
            }
            Divider()
            Button {
                folderAction()
            } label: {
                Image(systemName: "folder.fill")
                    .padding(.vertical, 10)
                    .padding(.trailing, 20)
                                               
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 16))
        .foregroundStyle(.black)
        .background(.procyonSecondary)
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .clipShape(.capsule)
        .frame(height: 30)
        .padding(.leading, 24)
    }
}

#Preview {
    PlayButtonExtras(playAction: {
    }, stopAction: {
    }, optionsAction: {
    }, editAction: {
    }, folderAction: {
    }, isPlaying: false)
}
