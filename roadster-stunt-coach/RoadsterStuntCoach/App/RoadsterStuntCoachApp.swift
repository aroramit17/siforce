import SwiftUI

@main
struct RoadsterStuntCoachApp: App {
    @State private var game = GameController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(game)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(GameController.self) private var game

    var body: some View {
        ZStack {
            Color.asphalt.ignoresSafeArea()
            switch game.phase {
            case .title:
                TitleView()
                    .transition(.opacity)
            case .cockpit:
                CockpitView()
                    .transition(.opacity)
            case .report:
                ClaimsReportView()
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: game.phase)
    }
}
