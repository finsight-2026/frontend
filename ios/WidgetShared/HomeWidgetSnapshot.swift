import Foundation

struct HomeWidgetSnapshot: Codable {
  var active = false
  var showScore = false
  var showType = false
  var showContent: Bool?
  var streakMonths = 0
  var lastDiagnosisDate: String?
  var nextDiagnosisDate: String?
  var score: Int?
  var type: String?
  var pressure: String?
  var maximumPressureScore: Int?
  var newsTitle: String?
  var newsDate: String?
  var newsId: String?
  var newsRevision: Int?
  var newsPublishedDate: String?
  var newsImage: Data?
  var newsCheckedAt: Date?
  var newsExpiresAt: Date?
  var actionTitle: String?
  var actionState: String?
  var actionAttemptId: String?
  var actionId: String?
  var actionRevision: Int?
  var actionDate: Date?

  static let kind = "FinsightHomeWidget"
  static let group = "group.kr.finsight.finsight"
  static let newsKind = "FinsightNewsWidget"
  static let actionKind = "FinsightActionWidget"
  static let openURL = URL(string: "finsight-widget://open")!
  static let recordURL = URL(string: "finsight-widget://open/record")!
  static let summaryURL = URL(string: "finsight-widget://open/summary")!
  static let newsURL = URL(string: "finsight-widget://open/news")!
  static let actionURL = URL(string: "finsight-widget://open/action")!

  var visibleScore: Int? {
    guard active, showScore, let score, (0...100).contains(score) else { return nil }
    return score
  }

  var visibleType: String? { active && showType ? type : nil }
  var visiblePressure: String? { active && showType ? pressure : nil }
  var visiblePressureScore: Int? {
    guard active, showScore, showType, let maximumPressureScore, (0...100).contains(maximumPressureScore) else { return nil }
    return maximumPressureScore
  }

  func visibleNews(at date: Date) -> Bool {
    guard active, showContent == true, newsTitle != nil, let newsExpiresAt else { return false }
    return date < newsExpiresAt
  }

  func newsByline(at date: Date) -> String {
    if let published = newsPublishedDate ?? newsDate, daysUntil(published, from: date) == 0 {
      return "오늘의 경제 한 장"
    }
    return "경제 한 장 · \(newsPublishedDate ?? newsDate ?? "")"
  }

  func newsCheckedLabel(at date: Date) -> String? {
    guard visibleNews(at: date), let newsCheckedAt else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = Self.calendar.timeZone
    formatter.dateFormat = "M.d HH:mm"
    return "\(formatter.string(from: newsCheckedAt)) 확인"
  }

  func newsDestination(at date: Date) -> URL {
    guard visibleNews(at: date), let newsId, let newsDate, let newsRevision else { return Self.newsURL }
    var components = URLComponents(url: Self.newsURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "id", value: newsId), URLQueryItem(name: "edition", value: newsDate),
                             URLQueryItem(name: "revision", value: String(newsRevision))]
    return components.url ?? Self.newsURL
  }

  func todayAction(at date: Date) -> String? {
    guard active, showContent == true, let actionDate, Self.calendar.isDate(actionDate, inSameDayAs: date) else { return nil }
    if let actionTitle { return actionTitle }
    switch actionState {
    case "NO_DIAGNOSIS": return "나에게 맞는 행동을 찾아볼까요"
    case "COMPLETE": return "이번 달 추천 행동을 모두 확인했어요"
    default: return nil
    }
  }

  func actionDestination(at date: Date) -> URL {
    guard todayAction(at: date) != nil, actionState == "AVAILABLE",
          let actionAttemptId, let actionId, let actionRevision else { return Self.actionURL }
    var components = URLComponents(url: Self.actionURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "attemptId", value: actionAttemptId),
      URLQueryItem(name: "id", value: actionId),
      URLQueryItem(name: "revision", value: String(actionRevision))
    ]
    return components.url ?? Self.actionURL
  }

  mutating func clearEditorialContent() {
    clearNews()
    actionTitle = nil
    actionState = nil
    actionAttemptId = nil
    actionId = nil
    actionRevision = nil
    actionDate = nil
  }

  mutating func clearNews() {
    newsTitle = nil
    newsDate = nil
    newsId = nil
    newsRevision = nil
    newsPublishedDate = nil
    newsImage = nil
    newsCheckedAt = nil
    newsExpiresAt = nil
  }

  private static func file() throws -> URL {
    guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return directory.appendingPathComponent("finsight-home-widget.json")
  }

  static func read() -> HomeWidgetSnapshot {
    do {
      return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file()))
    } catch {
      return Self()
    }
  }

  func write() throws {
    var url = try Self.file()
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  static func remove() throws {
    let url = try file()
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
  }

  func title(at date: Date) -> String {
    guard active else { return "앱에서 확인해주세요" }
    guard let nextDiagnosisDate else { return "첫 진단을 시작해보세요" }
    guard let days = daysUntil(nextDiagnosisDate, from: date) else { return "앱에서 확인해주세요" }
    if days < 0 { return "다시 점검해볼까요?" }
    return days == 0 ? "다음 진단 D-day" : "다음 진단 D-\(days)"
  }

  func recordTitle(at date: Date) -> String {
    guard active else { return "로그인하고 확인해보세요" }
    guard lastDiagnosisDate != nil else { return "첫 기록을 시작해보세요" }
    let months = streak(at: date)
    return months == 0 ? "다시 기록해볼까요" : "\(months)개월째 기록 중"
  }

  func recordSubtitle(at date: Date) -> String? {
    guard active else { return nil }
    guard lastDiagnosisDate != nil else { return "약 5분이면 돼요" }
    guard let nextDiagnosisDate, let days = daysUntil(nextDiagnosisDate, from: date) else { return nil }
    if days > 0 { return "다음 진단까지 D-\(days)" }
    return days == 0 ? "오늘 다시 점검해볼까요" : "다시 점검해볼까요"
  }

  private func daysUntil(_ value: String, from date: Date) -> Int? {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.calendar = Self.calendar
    format.timeZone = Self.calendar.timeZone
    format.dateFormat = "yyyy-MM-dd"
    guard let deadline = format.date(from: value) else { return nil }
    return Self.calendar.dateComponents([.day], from: Self.calendar.startOfDay(for: date), to: deadline).day
  }

  func streak(at date: Date) -> Int {
    let today = Self.calendar.dateComponents([.year, .month], from: date)
    guard let lastDiagnosisDate, let year = Int(lastDiagnosisDate.prefix(4)),
      let month = Int(lastDiagnosisDate.dropFirst(5).prefix(2)),
      let currentYear = today.year, let currentMonth = today.month
    else { return 0 }
    let offset = (currentYear - year) * 12 + currentMonth - month
    return (0...1).contains(offset) ? streakMonths : 0
  }
}
