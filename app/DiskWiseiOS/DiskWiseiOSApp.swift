import SwiftUI
import PhotosKit

@main
struct DiskWiseiOSApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
