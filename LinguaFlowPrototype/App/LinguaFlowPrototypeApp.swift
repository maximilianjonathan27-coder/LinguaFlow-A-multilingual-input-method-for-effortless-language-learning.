import LinguaFlowCore
import SwiftUI

@main
struct LinguaFlowPrototypeApp: App {
    @State private var exposureStore = ExposureStore(legacyDefaults: .standard)

    var body: some Scene {
        WindowGroup("LinguaFlow Setup") {
            ContentView(exposureStore: exposureStore)
                .frame(minWidth: 680, minHeight: 500)
        }
        .defaultSize(width: 760, height: 590)
        .windowResizability(.contentMinSize)
    }
}
