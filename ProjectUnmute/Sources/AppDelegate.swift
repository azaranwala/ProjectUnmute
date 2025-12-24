import UIKit
import os.log

final class AppDelegate: NSObject, UIApplicationDelegate {
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "AppDelegate")
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureSDKs()
        return true
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
        
        // Meta Wearables SDK setup (add via SPM)
        // import WearablesDeviceAccessToolkit
        // WearablesDeviceAccess.shared.configure()
        
        // MediaPipe is configured per-use in the view controller
    }
}
