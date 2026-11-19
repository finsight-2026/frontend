import Flutter
import AuthenticationServices
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    HomeWidgetBridge.shared.attach(messenger)
    PasswordResetLinks.shared.attach(messenger)
    NotificationOpens.shared.attach(messenger)
    FcmRegistrationBridge.shared.attach(messenger)
    SocialWebAuthentication.shared.attach(messenger)
    let notifications = FlutterMethodChannel(name: "finsight/notification_permissions", binaryMessenger: messenger)
    notifications.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "status":
        Self.readNotificationPermission(center, result)
      case "request":
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, error in
          if error != nil {
            DispatchQueue.main.async {
              result(FlutterError(code: "NOTIFICATION_PERMISSION", message: nil, details: nil))
            }
          } else {
            Self.readNotificationPermission(center, result)
          }
        }
      case "openSettings":
        let address: String
        if #available(iOS 16.0, *) {
          address = UIApplication.openNotificationSettingsURLString
        } else {
          address = UIApplication.openSettingsURLString
        }
        guard let url = URL(string: address) else {
          result(false)
          return
        }
        UIApplication.shared.open(url) { opened in result(opened) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    FcmRegistrationBridge.shared.registered(deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    FcmRegistrationBridge.shared.registrationFailed()
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NotificationOpens.shared.receive(response)
    completionHandler()
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  private static func readNotificationPermission(_ center: UNUserNotificationCenter, _ result: @escaping FlutterResult) {
    center.getNotificationSettings { settings in
      let status: String
      switch settings.authorizationStatus {
      case .notDetermined: status = "notDetermined"
      case .denied: status = "denied"
      case .authorized, .provisional, .ephemeral: status = "allowed"
      @unknown default: status = "unknown"
      }
      DispatchQueue.main.async { result(status) }
    }
  }
}

final class SocialWebAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
  static let shared = SocialWebAuthentication()
  private static let allowedHosts = ["kauth.kakao.com", "appleid.apple.com"]
  private var authentication: ASWebAuthenticationSession?
  private var window: ASPresentationAnchor?

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "finsight/social_authentication", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "authenticate" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard self.authentication == nil,
            let options = call.arguments as? [String: Any],
            let address = options["url"] as? String,
            let url = URL(string: address), url.scheme == "https", url.port == nil,
            url.user == nil, url.password == nil, let host = url.host,
            Self.allowedHosts.contains(host),
            let window = UIApplication.shared.connectedScenes
              .compactMap({ $0 as? UIWindowScene })
              .first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
      else {
        result(FlutterError(code: "SOCIAL_AUTHENTICATION", message: nil, details: nil))
        return
      }
      self.window = window
      let authentication = ASWebAuthenticationSession(url: url, callbackURLScheme: "finsight-social") {
        [weak self] callback, error in
        DispatchQueue.main.async {
          self?.authentication = nil
          self?.window = nil
          if let callback {
            result(callback.absoluteString)
          } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
            result(nil)
          } else {
            result(FlutterError(code: "SOCIAL_AUTHENTICATION", message: nil, details: nil))
          }
        }
      }
      authentication.presentationContextProvider = self
      authentication.prefersEphemeralWebBrowserSession = options["reauthenticate"] as? Bool == true
      self.authentication = authentication
      if !authentication.start() {
        self.authentication = nil
        self.window = nil
        result(FlutterError(code: "SOCIAL_AUTHENTICATION", message: nil, details: nil))
      }
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    window ?? ASPresentationAnchor()
  }
}

final class PasswordResetLinks {
  static let shared = PasswordResetLinks()
  private var channel: FlutterMethodChannel?
  private var pending: String?

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "finsight/password_reset_links", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "take" else { result(FlutterMethodNotImplemented); return }
      let token = self?.pending
      self?.pending = nil
      result(token)
    }
    self.channel = channel
  }

  func receive(_ url: URL) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.user == nil, components.password == nil, components.port == nil,
          components.percentEncodedPath == "/password-reset", components.query == nil else { return false }
    let universal = components.scheme == "https" && components.host == "finsight.life"
    #if DEBUG
    let local = components.scheme == "finsight-reset" && components.host == "local"
    #else
    let local = false
    #endif
    guard universal || local,
          let fragment = components.percentEncodedFragment, fragment.hasPrefix("token=") else { return false }
    let token = String(fragment.dropFirst(6))
    guard token.utf8.count == 43,
          token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return false }
    if pending != token {
      pending = token
      channel?.invokeMethod("open", arguments: nil)
    }
    return true
  }
}

final class NotificationOpens {
  static let shared = NotificationOpens()
  private var channel: FlutterMethodChannel?
  private var pending: String?
  private var last: (id: UUID, time: TimeInterval)?

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "finsight/notification_opens", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "peek":
        result(self.pending != nil)
      case "take":
        let id = self.pending
        self.pending = nil
        result(id)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func receive(_ response: UNNotificationResponse) {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
          let raw = response.notification.request.content.userInfo["notification_id"] as? String,
          let id = UUID(uuidString: raw) else { return }
    DispatchQueue.main.async {
      let now = ProcessInfo.processInfo.systemUptime
      if let last = self.last, last.id == id, now - last.time < 1 { return }
      self.last = (id, now)
      self.pending = id.uuidString.lowercased()
      self.channel?.invokeMethod("open", arguments: nil)
    }
  }
}
