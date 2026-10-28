import SwiftUI

@main
struct RoadsterStuntCoachApp: App {
    @StateObject private var game = GameController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var game: GameController

    var body: some View {
        ZStack {
            Color.asphalt.ignoresSafeArea()
            switch game.phase {
            case .title:
                TitleView()
                    .transition(.opacity)
            case .countdown, .running:
                RunView()
                    .transition(.opacity)
            case .finished:
                ClaimsReportView()
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: game.phase)
    }
}
