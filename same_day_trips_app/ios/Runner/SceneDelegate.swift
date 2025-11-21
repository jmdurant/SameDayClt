import Flutter
import UIKit

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    // Create window for this scene
    window = UIWindow(windowScene: windowScene)

    // Use the shared FlutterEngine from AppDelegate
    // This ensures both iPhone and CarPlay use the same Flutter instance
    let flutterViewController = FlutterViewController(
      engine: flutterEngine!,
      nibName: nil,
      bundle: nil
    )

    // Set the Flutter view controller as the root
    window?.rootViewController = flutterViewController
    window?.makeKeyAndVisible()
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    // Called as the scene is being released by the system
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    // Called when the scene has moved from an inactive state to an active state
  }

  func sceneWillResignActive(_ scene: UIScene) {
    // Called when the scene will move from an active state to an inactive state
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    // Called as the scene transitions from the background to the foreground
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    // Called as the scene transitions from the foreground to the background
  }
}
