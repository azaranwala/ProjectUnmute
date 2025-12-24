import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeRootViewController()
        window.makeKeyAndVisible()
        self.window = window
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
    
    // MARK: - Factory
    
    private func makeRootViewController() -> UIViewController {
        let mainVC = MainViewController()
        let nav = UINavigationController(rootViewController: mainVC)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
}
