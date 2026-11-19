import Flutter
import UIKit
import UserNotifications

class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    if let window, privacyCover == nil {
      let cover = UIView(frame: window.bounds)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.backgroundColor = .black
      cover.accessibilityViewIsModal = true

      let logo = UIImageView(image: UIImage(named: "LaunchImage"))
      logo.contentMode = .scaleAspectFit
      logo.translatesAutoresizingMaskIntoConstraints = false
      cover.addSubview(logo)
      NSLayoutConstraint.activate([
        logo.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
        logo.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
      ])

      window.addSubview(cover)
      privacyCover = cover
    }
    super.sceneWillResignActive(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
    super.sceneDidBecomeActive(scene)
  }

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    if let context = connectionOptions.urlContexts.first(where: { HomeWidgetBridge.shared.accepts($0.url) }) {
      HomeWidgetBridge.shared.open(context.url)
    }
    for context in connectionOptions.urlContexts {
      _ = PasswordResetLinks.shared.receive(context.url)
    }
    for activity in connectionOptions.userActivities {
      _ = receivePasswordReset(activity)
    }
    if let response = connectionOptions.notificationResponse {
      NotificationOpens.shared.receive(response)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let other = URLContexts.filter { context in
      if HomeWidgetBridge.shared.accepts(context.url) {
        HomeWidgetBridge.shared.open(context.url)
        return false
      }
      return !PasswordResetLinks.shared.receive(context.url)
    }
    if !other.isEmpty { super.scene(scene, openURLContexts: other) }
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if !receivePasswordReset(userActivity) { super.scene(scene, continue: userActivity) }
  }

  private func receivePasswordReset(_ activity: NSUserActivity) -> Bool {
    guard activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL else { return false }
    return PasswordResetLinks.shared.receive(url)
  }
}
