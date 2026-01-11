import SwiftUI

@main
struct ProjectUnmuteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // SceneDelegate handles all URL callbacks to avoid duplicate processing
                    print("ℹ️ SwiftUI onOpenURL - SceneDelegate will handle: \(url)")
                }
        }
    }
}
