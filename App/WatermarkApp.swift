import SwiftUI

@main
struct WatermarkApp: App {
    @State private var viewModel = WatermarkViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
