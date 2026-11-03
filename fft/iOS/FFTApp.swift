import SwiftUI

@main
struct FFTApp: App {
    @StateObject private var engine = TestEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .tint(.red)
        }
    }
}
