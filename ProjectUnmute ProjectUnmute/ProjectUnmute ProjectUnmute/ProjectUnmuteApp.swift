import SwiftUI
import MWDATCore

@main
struct ProjectUnmuteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    print("📱 SwiftUI received URL: \(url)")
                    // Handle Meta Wearables SDK callback
                    Task { @MainActor in
                        do {
                            let handled = try await Wearables.shared.handleUrl(url)
                            print(handled ? "✅ Meta SDK handled URL (SwiftUI)" : "⚠️ Meta SDK did not handle URL")
                            
                            // If handled, restart streaming
                            if handled {
                                print("🔄 Restarting Meta Glasses streaming after authorization...")
                                await MetaGlassesCameraManager.shared.startStreaming()
                            }
                        } catch {
                            print("❌ Error handling URL: \(error)")
                        }
                    }
                }
        }
    }
}
