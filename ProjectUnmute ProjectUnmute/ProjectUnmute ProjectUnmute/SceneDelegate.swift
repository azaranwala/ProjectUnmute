import UIKit
import SwiftUI
import MWDATCore

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        let window = UIWindow(windowScene: windowScene)
        // Use SwiftUI ContentView as root (has full Speech→ASL and ASL→Text functionality)
        let contentView = ContentView()
        window.rootViewController = UIHostingController(rootView: contentView)
        window.makeKeyAndVisible()
        self.window = window
        
        // Handle Universal Links passed at launch
        if let urlContext = connectionOptions.urlContexts.first {
            print("🔗 SceneDelegate launch URL: \(urlContext.url)")
            handleIncomingURL(urlContext.url)
        }
        
        // Handle Universal Links from user activities
        if let userActivity = connectionOptions.userActivities.first,
           userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            print("🌐 SceneDelegate launch Universal Link: \(url)")
            handleIncomingURL(url)
        }
    }
    
    // MARK: - URL Handling for Meta SDK
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        print("📱 SceneDelegate received URL: \(url)")
        handleIncomingURL(url)
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        // Handle Universal Links
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        print("🌐 SceneDelegate received Universal Link: \(url)")
        handleIncomingURL(url)
    }
    
    private func handleIncomingURL(_ url: URL) {
        Task { @MainActor in
            do {
                let handled = try await Wearables.shared.handleUrl(url)
                print(handled ? "✅ Meta SDK handled URL" : "⚠️ Meta SDK did not handle URL")
                
                if handled {
                    // Restart streaming after successful registration
                    print("🔄 Registration successful, restarting streaming...")
                    await MetaGlassesCameraManager.shared.startStreaming()
                }
            } catch {
                print("❌ Error handling URL: \(error)")
            }
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Release resources associated with this scene.
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Restart paused tasks or refresh UI.
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        // Pause ongoing tasks or disable timers.
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        // Undo changes made on entering background.
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Save data, release shared resources, store scene state.
    }
}
