//
//  GameView.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI

private let gameGridColumnCount = 3
private let gameGridSpacing: CGFloat = 10
private let gameGridHorizontalPadding: CGFloat = 16

struct GamesList: View {
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var compatibilityStore: GameCompatibilityStore
    
    var load: @Sendable () async -> Void

    private var filteredGames: [Game] {
        libraryPageGlobals.filteredGames { game in
            compatibilityStore.isPlayableOnMac(game)
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            let cardWidth = max(
                (proxy.size.width
                    - gameGridHorizontalPadding * 2
                    - gameGridSpacing * CGFloat(gameGridColumnCount - 1))
                    / CGFloat(gameGridColumnCount),
                1
            )
            let cardHeight = appWindowResizable ? cardWidth / 1.52 : 214
            let gridColumns = Array(
                repeating: GridItem(.fixed(cardWidth), spacing: gameGridSpacing),
                count: gameGridColumnCount
            )

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: gameGridSpacing) {
                    ForEach(filteredGames) { item in
                        GameThumbnail(
                            item: item,
                            isResizable: appWindowResizable,
                            fixedCardWidth: cardWidth,
                            fixedCardHeight: cardHeight
                        )
                            .frame(width: cardWidth, height: cardHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    }
                }
                .padding(.horizontal, gameGridHorizontalPadding)
                .padding(.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
