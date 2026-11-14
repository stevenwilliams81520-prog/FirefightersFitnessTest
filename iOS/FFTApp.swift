import SwiftUI

@main
struct FFTApp: App {
    @StateObject private var engine = TestEngine()
    @StateObject private var store = Store()
    @StateObject private var ads = AdsManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(store)
                .environmentObject(ads)
                .tint(.red)
                .task { ads.prepare() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.pushConfig() }
        }
    }
}
