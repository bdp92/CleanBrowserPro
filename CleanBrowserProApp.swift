import SwiftUI

@main
struct CleanBrowserProApp: App {
    @StateObject private var browser = BrowserModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environmentObject(browser)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                browser.resetPrivateSession(reason: "App naar achtergrond")
            }
        }
    }
}
