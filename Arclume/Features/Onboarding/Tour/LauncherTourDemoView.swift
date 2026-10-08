import SwiftUI

/// An ephemeral empty-library illustration using the production launcher layout.
/// It is never registered, saved, installed or passed to a launch action.
struct LauncherTourDemoView: View {
    private var game: Game {
        var game = Game.emptyGame
        game.id = "arclume.tour.demo"
        game.name = "我的第一个游戏"
        game.shortDescription = "添加游戏后，这里会显示它的介绍和运行信息。当前是引导演示项目。"
        game.isNative = true
        game.isInstalled = false
        return game
    }
    var body: some View {
        ZStack(alignment: .leading) {
            LauncherGameHomeView(game: game, onLaunchJX3: {}, onStopJX3: {}, isPreview: true)
            VStack(spacing: 18) {
                VStack(spacing: 22) {
                    Image("Arclume").resizable().scaledToFit().frame(width: 46, height: 46)
                    Image(systemName: "gamecontroller.fill").font(.system(size: 30))
                    Image(systemName: "app.dashed").font(.system(size: 30))
                    Spacer()
                }
                .padding(14).frame(width: 74)
                .glassEffect(in: .rect(cornerRadius: 22))
                .launcherTourTarget(.sidebar)
                Image(systemName: "square.grid.3x3.fill").frame(width: 74, height: 36)
                    .glassEffect().launcherTourTarget(.allGames)
                Image(systemName: "chevron.left").frame(width: 74, height: 36)
                    .glassEffect().launcherTourTarget(.collapse)
            }
            .foregroundStyle(.white).padding(.leading, 14).padding(.top, 72).padding(.bottom, 18)
        }
        .allowsHitTesting(false)
    }
}
