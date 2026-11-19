import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

final class FcmRegistrationBridge: NSObject {
  static let shared = FcmRegistrationBridge()
  private var channel: FlutterMethodChannel?

  private var active = false
  private var registeringAPNs = false
  private var registeringFirebase = false
  private var requestedRegistration = false
  private var deleting = false
  private var installationID: String?
  private var generation = 0

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "finsight/fcm_registration", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "registrationId":
        self.registrationID(result)
      case "suspend":
        self.suspend()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func registrationID(_ result: @escaping FlutterResult) {
    if FirebaseApp.app() == nil {
      guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let options = FirebaseOptions(contentsOfFile: path),
            options.bundleID == Bundle.main.bundleIdentifier else {
        result(FlutterError(code: "FCM_NOT_CONFIGURED", message: nil, details: nil))
        return
      }
      FirebaseApp.configure(options: options)
    }
    active = true
    let messaging = Messaging.messaging()
    messaging.delegate = self
    if deleting {
      result(FlutterError(code: "FCM_NOT_READY", message: nil, details: nil))
      return
    }
    if messaging.apnsToken == nil {
      if !registeringAPNs {
        registeringAPNs = true
        UIApplication.shared.registerForRemoteNotifications()
      }
      result(FlutterError(code: "APNS_NOT_READY", message: nil, details: nil))
      return
    }
    if let installationID {
      result(installationID)
      return
    }
    if !registeringFirebase {
      registeringFirebase = true
      requestedRegistration = true
      let requestedGeneration = generation
      messaging.register { error in
        DispatchQueue.main.async {
          guard self.generation == requestedGeneration else { return }
          self.registeringFirebase = false
          if error != nil { self.requestedRegistration = false }
        }
      }
    }
    result(FlutterError(code: "FCM_NOT_READY", message: nil, details: nil))
  }

  func registered(_ deviceToken: Data) {
    registeringAPNs = false
    guard active, FirebaseApp.app() != nil else { return }
    Messaging.messaging().apnsToken = deviceToken
    channel?.invokeMethod("changed", arguments: nil)
  }

  func registrationFailed() {
    registeringAPNs = false
  }

  private func suspend() {
    guard active, FirebaseApp.app() != nil else { return }
    generation += 1
    active = false
    registeringAPNs = false
    registeringFirebase = false
    requestedRegistration = false
    installationID = nil
    UIApplication.shared.unregisterForRemoteNotifications()
    let messaging = Messaging.messaging()
    messaging.apnsToken = nil
    if !deleting {
      deleting = true
      messaging.unregister { _ in
        DispatchQueue.main.async {
          self.deleting = false
          if self.active { self.channel?.invokeMethod("changed", arguments: nil) }
        }
      }
    }
  }
}

extension FcmRegistrationBridge: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistration installationID: String?) {
    DispatchQueue.main.async {
      guard self.active, !self.deleting, self.requestedRegistration, let installationID else { return }
      self.registeringFirebase = false
      if self.installationID != installationID {
        self.installationID = installationID
        self.channel?.invokeMethod("changed", arguments: nil)
      }
    }
  }
}
