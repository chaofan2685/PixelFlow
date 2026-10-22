import SwiftUI

@main
struct PixelFlowApp: App {
    var body: some Scene {
        WindowGroup {
            ScannerView()
                .preferredColorScheme(.dark)
        }
    }
}
