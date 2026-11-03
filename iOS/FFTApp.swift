import SwiftUI

@main
struct FFTApp: App {
    @StateObject private var engine = TestEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .tint(.red)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.pushConfig() }
        }
    }
}
