import SwiftUI
import WatchConnectivity

@main
struct WristAIApp: App {
    @StateObject private var bridge = PhoneWatchBridge.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bridge)
                .environmentObject(settings)
                .onAppear { bridge.activate() }
        }
    }
}
