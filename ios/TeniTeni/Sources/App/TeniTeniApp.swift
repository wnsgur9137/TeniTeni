import SwiftUI

@main
struct TeniTeniApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
                .preferredColorScheme(.dark)
        }
    }
}
