import Flutter
import UIKit

// Shared FlutterEngine for both iPhone and CarPlay
var flutterEngine: FlutterEngine?

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Create shared FlutterEngine with headless execution enabled
    // This allows CarPlay to launch even when the app is not running
    flutterEngine = FlutterEngine(name: "SharedEngine", project: nil, allowHeadlessExecution: true)

    // Run the engine
    flutterEngine?.run()

    // Register all Flutter plugins with the shared engine
    GeneratedPluginRegistrant.register(with: flutterEngine!)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Support for scene-based lifecycle (iOS 13+)
  override func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    // Determine which scene configuration to use
    if connectingSceneSession.role == .carTemplateApplication {
      // CarPlay scene - handled by flutter_carplay plugin
      let sceneConfig = UISceneConfiguration(
        name: "CarPlay Configuration",
        sessionRole: connectingSceneSession.role
      )
      sceneConfig.delegateClass = NSClassFromString("flutter_carplay.FlutterCarPlaySceneDelegate")
      return sceneConfig
    } else {
      // Standard app scene - handled by our SceneDelegate
      let sceneConfig = UISceneConfiguration(
        name: "Default Configuration",
        sessionRole: connectingSceneSession.role
      )
      sceneConfig.delegateClass = SceneDelegate.self
      return sceneConfig
    }
  }
}
