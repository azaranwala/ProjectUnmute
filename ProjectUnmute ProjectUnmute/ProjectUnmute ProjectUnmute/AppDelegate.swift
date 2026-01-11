import UIKit
import os.log
import MWDATCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "AppDelegate")
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureSDKs()
        return true
    }
    
    // MARK: - URL Handling for Meta SDK
    
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        logger.info("📱 Received URL: \(url.absoluteString)")
        print("📱 AppDelegate received URL: \(url)")
        
        // Let SceneDelegate handle URLs to avoid duplicate processing
        // SceneDelegate.scene(_:openURLContexts:) will handle this
        print("ℹ️ AppDelegate URL - delegating to SceneDelegate")
        return false
    }
    
    // MARK: - Universal Link Handling
    
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        
        logger.info("🌐 AppDelegate received Universal Link: \(url.absoluteString)")
        print("🌐 AppDelegate Universal Link: \(url)")
        
        // Let SceneDelegate handle Universal Links to avoid duplicate processing
        print("ℹ️ AppDelegate Universal Link - delegating to SceneDelegate")
        return false
    }
    
    // MARK: - UISceneSession Lifecycle
    
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // Called when the user discards a scene session.
    }
    
    // MARK: - SDK Configuration
    
    private func configureSDKs() {
        logger.info("Configuring SDKs...")
        
        // Meta Wearables SDK is configured in MetaGlassesCameraManager
        // via Wearables.configure()
    }
}
