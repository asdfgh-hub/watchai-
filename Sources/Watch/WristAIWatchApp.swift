import SwiftUI
import WatchConnectivity

@main
struct WristAIWatchApp: App {
    @StateObject private var bridge = WatchBridge.shared
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(bridge)
                .onAppear { bridge.activate() }
        }
    }
}
