import SwiftUI

@main
struct LinguaFlowPrototypeApp: App {
    var body: some Scene {
        WindowGroup("LinguaFlow") {
            ContentView()
                .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
        }
    }
}
