import SwiftUI

@main
struct LinguaFlowPrototypeApp: App {
    @State private var exposureStore = ExposureStore()

    var body: some Scene {
        WindowGroup("LinguaFlow") {
            ContentView(exposureStore: exposureStore)
                .frame(minWidth: 680, minHeight: 500)
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)
    }
}
