import Flutter
import Foundation
import WidgetKit

final class HomeWidgetBridge {
  static let shared = HomeWidgetBridge()
  private var channel: FlutterMethodChannel?
  private var pendingOpen: String?

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "finsight/home_widget", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    self.channel = channel
  }

  func accepts(_ url: URL) -> Bool {
    destination(for: url) != nil
  }

  func open(_ url: URL) {
    guard let destination = destination(for: url) else { return }
    pendingOpen = destination
    channel?.invokeMethod("open", arguments: nil)
  }

  private func destination(for url: URL) -> String? {
    guard url.scheme == "finsight-widget", url.host == "open" else { return nil }
    switch url.path {
    case "": return "default"
    case "/record": return "diagnosis"
    case "/summary": return "default"
    case "/news", "/action":
      let kind = String(url.path.dropFirst())
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
      return query.map { "\(kind)?\($0)" } ?? kind
    default: return nil
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
    do {
      var snapshot = HomeWidgetSnapshot.read()
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "options":
        if #available(iOS 14.0, *),
          FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HomeWidgetSnapshot.group) != nil {
          result(["showScore": snapshot.showScore, "showType": snapshot.showType, "showContent": snapshot.showContent == true])
        } else {
          result(nil)
        }
      case "configure":
        snapshot.showScore = args["showScore"] as? Bool ?? false
        snapshot.showType = args["showType"] as? Bool ?? false
        snapshot.showContent = args["showContent"] as? Bool ?? false
        if snapshot.showContent != true { snapshot.clearEditorialContent() }
        if !snapshot.showScore { snapshot.score = nil }
        if !snapshot.showScore || !snapshot.showType { snapshot.maximumPressureScore = nil }
        if !snapshot.showType {
          snapshot.type = nil
          snapshot.pressure = nil
        }
        try snapshot.write()
        reload()
        result(nil)
      case "publish", "clearData":
        snapshot.active = true
        snapshot.streakMonths = args["streakMonths"] as? Int ?? 0
        snapshot.lastDiagnosisDate = args["lastDiagnosisDate"] as? String
        snapshot.nextDiagnosisDate = args["nextDiagnosisDate"] as? String
        snapshot.score = snapshot.showScore ? args["score"] as? Int : nil
        snapshot.type = snapshot.showType ? args["type"] as? String : nil
        snapshot.pressure = snapshot.showType ? args["pressure"] as? String : nil
        snapshot.maximumPressureScore = snapshot.showScore && snapshot.showType ? args["maximumPressureScore"] as? Int : nil
        if snapshot.showContent == true && call.method == "publish" {
          refreshNews(&snapshot, args: args)
          snapshot.actionTitle = args["actionTitle"] as? String
          snapshot.actionState = args["actionState"] as? String
          snapshot.actionAttemptId = args["actionAttemptId"] as? String
          snapshot.actionId = args["actionId"] as? String
          snapshot.actionRevision = args["actionRevision"] as? Int
          snapshot.actionDate = snapshot.actionState == nil ? nil : Date()
        } else {
          snapshot.clearEditorialContent()
        }
        try snapshot.write()
        reload()
        result(nil)
      case "clear":
        try HomeWidgetSnapshot.remove()
        reload()
        result(nil)
      case "peekOpen":
        result(pendingOpen != nil)
      case "consumeOpen":
        let value = pendingOpen
        pendingOpen = nil
        result(value)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "HOME_WIDGET", message: "위젯 설정을 처리하지 못했습니다.", details: nil))
    }
  }

  private func reload() {
    WidgetCenter.shared.reloadAllTimelines()
  }

  private func refreshNews(_ snapshot: inout HomeWidgetSnapshot, args: [String: Any]) {
    let now = Date()
    if args["keepNews"] as? Bool == true && snapshot.visibleNews(at: now) { return }
    snapshot.clearNews()
    guard let id = args["newsId"] as? String, let title = args["newsTitle"] as? String,
          let edition = args["newsDate"] as? String, let revision = args["newsRevision"] as? Int else { return }
    let format = ISO8601DateFormatter()
    var deadline = now.addingTimeInterval(86400)
    if let endsAt = args["newsEndsAt"] as? String {
      var end = format.date(from: endsAt)
      if end == nil {
        format.formatOptions.insert(.withFractionalSeconds)
        end = format.date(from: endsAt)
      }
      guard let end, end > now else { return }
      deadline = min(deadline, end)
    }
    snapshot.newsId = id
    snapshot.newsTitle = title
    snapshot.newsDate = edition
    snapshot.newsRevision = revision
    snapshot.newsPublishedDate = args["newsPublishedDate"] as? String
    if let image = (args["newsImage"] as? FlutterStandardTypedData)?.data,
       image.count <= 400 * 1024 {
      snapshot.newsImage = image
    }
    snapshot.newsCheckedAt = now
    snapshot.newsExpiresAt = deadline
  }
}
