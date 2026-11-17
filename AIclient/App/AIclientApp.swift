import SwiftUI

@main
struct AIclientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
        #endif
    }
}
