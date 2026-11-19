import SwiftUI
import UIKit
import WidgetKit

private struct Entry: TimelineEntry {
  let date: Date
  let snapshot: HomeWidgetSnapshot
}

private struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> Entry {
    Entry(date: Date(), snapshot: HomeWidgetSnapshot())
  }

  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    completion(Entry(date: Date(), snapshot: context.isPreview ? HomeWidgetSnapshot() : .read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let now = Date()
    let calendar = HomeWidgetSnapshot.calendar
    let start = calendar.startOfDay(for: now)
    let next = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86400)
    let snapshot = HomeWidgetSnapshot.read()
    var dates = [now, next]
    if let expiry = snapshot.newsExpiresAt, expiry > now && expiry != next { dates.append(expiry) }
    completion(Timeline(entries: dates.sorted().map { Entry(date: $0, snapshot: snapshot) }, policy: .after(next)))
  }
}

private struct Content: View {
  @Environment(\.widgetFamily) private var family
  let entry: Entry
  var editorial: EditorialKind? = nil
  private let lime = Color(red: 0.78, green: 1, blue: 0)
  private var cardBackground: some View {
    RadialGradient(colors: [Color(red: 0.14, green: 0.17, blue: 0.06), Color(red: 0.055, green: 0.064, blue: 0.066)],
                   center: .top, startRadius: 4, endRadius: 126)
  }

  private func artwork(_ name: String, fallback: String) -> Image {
    if let url = Bundle.main.url(forResource: name, withExtension: "png"),
       let image = UIImage(contentsOfFile: url.path) {
      return Image(uiImage: image)
    }
    return Image(systemName: fallback)
  }

  @ViewBuilder
  var body: some View {
    if #available(iOSApplicationExtension 17.0, *), family == .accessoryRectangular {
      reminder.containerBackground(.clear, for: .widget)
    } else if #available(iOSApplicationExtension 16.0, *), family == .accessoryRectangular {
      reminder
    } else if #available(iOSApplicationExtension 17.0, *) {
      homeContent.containerBackground(for: .widget) { cardBackground }
    } else {
      homeContent.padding().background(cardBackground)
    }
  }

  @ViewBuilder
  private var homeContent: some View {
    switch editorial {
    case .news: news
    case .action: action
    case nil: if family == .systemSmall { record } else { summary }
    }
  }

  private var news: some View {
    let snapshot = entry.snapshot
    let ready = snapshot.visibleNews(at: entry.date)
    let fallback = !snapshot.active ? "로그인하고 확인해보세요" :
      (snapshot.showContent == true ? "경제 소식을 준비하고 있어요" : "새 경제 소식을 확인해보세요")
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text("MORNING BRIEF").font(.caption2.bold()).tracking(1).foregroundColor(lime)
        Text(ready ? snapshot.newsTitle ?? fallback : fallback)
          .font(.system(size: 19, weight: .bold)).lineLimit(2).minimumScaleFactor(0.75)
        if ready {
          Text(snapshot.newsByline(at: entry.date)).font(.caption2).foregroundColor(.white.opacity(0.72))
        }
        if let checked = snapshot.newsCheckedLabel(at: entry.date) {
          Text(checked).font(.caption2).foregroundColor(.white.opacity(0.72))
        }
        Image(systemName: "arrow.right.circle.fill").foregroundColor(lime).accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Group {
        if ready, let data = snapshot.newsImage, let image = UIImage(data: data) {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          artwork("widget-news", fallback: "newspaper").resizable().scaledToFit()
        }
      }
        .frame(width: 93, height: 93).clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
    .foregroundColor(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .widgetURL(snapshot.newsDestination(at: entry.date))
  }

  private var action: some View {
    let snapshot = entry.snapshot
    let fallback = !snapshot.active ? "로그인하고 확인해보세요" :
      (snapshot.showContent == true ? "추천 행동을 준비하고 있어요" : "오늘의 작은 행동")
    return VStack(alignment: .leading, spacing: 6) {
      Text("TODAY’S ACTION").font(.caption2.bold()).tracking(0.75).foregroundColor(lime)
        .lineLimit(1).minimumScaleFactor(0.8)
      Text(snapshot.todayAction(at: entry.date) ?? fallback)
        .font(.system(size: 19, weight: .bold)).lineLimit(3).minimumScaleFactor(0.76)
      if snapshot.active && snapshot.showContent != true {
        Text("앱에서 확인해보세요").font(.caption2).foregroundColor(.white.opacity(0.72))
      }
      Spacer(minLength: 0)
      artwork("widget-action", fallback: "checkmark.circle.fill").resizable().scaledToFit()
        .frame(width: 38, height: 38).clipShape(Circle())
        .frame(maxWidth: .infinity, alignment: .trailing).accessibilityHidden(true)
    }
    .foregroundColor(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .combine)
    .widgetURL(snapshot.actionDestination(at: entry.date))
  }

  private var record: some View {
    VStack(spacing: 4) {
      artwork("widget-calendar", fallback: "calendar.badge.checkmark").resizable().scaledToFit()
        .frame(width: 66, height: 66).clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
      HStack(spacing: 4) {
        ForEach(0..<3) { _ in Circle().fill(lime).frame(width: 4, height: 4) }
      }
      .accessibilityHidden(true)
      Text(entry.snapshot.recordTitle(at: entry.date))
        .font(.system(size: 18, weight: .bold)).lineLimit(2).minimumScaleFactor(0.76)
      if let subtitle = entry.snapshot.recordSubtitle(at: entry.date) {
        Text(subtitle).font(.caption2).foregroundColor(.white.opacity(0.72))
          .lineLimit(2).minimumScaleFactor(0.85)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .foregroundColor(.white)
    .accessibilityElement(children: .combine)
    .widgetURL(HomeWidgetSnapshot.recordURL)
  }

  private var reminder: some View {
    VStack(alignment: .leading) {
      Text("FINSIGHT").font(.caption.weight(.bold))
      Text("금융 습관을 점검해보세요").font(.caption)
    }
    .widgetURL(HomeWidgetSnapshot.openURL)
  }

  private var summary: some View {
    let snapshot = entry.snapshot
    return HStack(spacing: 16) {
      ZStack {
        Circle().strokeBorder(.white.opacity(0.16), lineWidth: 8)
        if let score = snapshot.visibleScore {
          Circle().trim(from: 0, to: CGFloat(score) / 100)
            .stroke(AngularGradient(colors: [lime, lime.opacity(0.68), lime], center: .center),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round))
            .rotationEffect(.degrees(-90)).padding(5)
            .shadow(color: lime.opacity(0.45), radius: 7)
          VStack(spacing: 0) {
            Text("\(score)").font(.system(size: 36, weight: .bold)).foregroundColor(lime)
            Text("/100").font(.caption2).foregroundColor(.white.opacity(0.72))
          }
          .accessibilityLabel("금융 부담 점수 \(score)점, 높을수록 부담이 커요")
        } else {
          Image(systemName: "waveform.path").font(.title2).foregroundColor(lime)
            .accessibilityHidden(true)
        }
      }
      .frame(width: 101, height: 101)
      VStack(alignment: .leading, spacing: 5) {
        if let type = snapshot.visibleType {
          Text(type).font(.caption2.bold()).foregroundColor(lime)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(lime.opacity(0.16), in: Capsule())
        }
        if let pressure = snapshot.visiblePressure {
          Text("가장 큰 금융 압박").font(.caption2).foregroundColor(.white.opacity(0.72))
          Text(pressure).font(.system(size: 18, weight: .bold)).lineLimit(2).minimumScaleFactor(0.78)
          if let score = snapshot.visiblePressureScore {
            ProgressView(value: Double(score), total: 100).tint(lime)
              .accessibilityLabel("가장 큰 금융 압박 \(score)점")
            if score == 0 {
              Text("모든 영역의 부담이 낮아요").font(.caption2).foregroundColor(.white.opacity(0.72))
            }
          }
        } else {
          let title = snapshot.lastDiagnosisDate == nil ? snapshot.title(at: entry.date) : "나의 금융 마음"
          Text(title).font(.headline).lineLimit(2).minimumScaleFactor(0.85)
          if snapshot.lastDiagnosisDate != nil && snapshot.visibleScore == nil {
            Text("앱에서 확인하기").font(.caption2).foregroundColor(.white.opacity(0.72))
          }
        }
        if snapshot.active, snapshot.lastDiagnosisDate != nil {
          Label("맞춤 가이드 보기", systemImage: "chevron.right").font(.caption2.bold()).foregroundColor(lime)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .foregroundColor(.white)
    .accessibilityElement(children: .combine)
    .widgetURL(HomeWidgetSnapshot.summaryURL)
  }
}

struct FinsightHomeWidget: Widget {
  private var families: [WidgetFamily] {
    if #available(iOSApplicationExtension 16.0, *) {
      return [.systemSmall, .systemMedium, .accessoryRectangular]
    }
    return [.systemSmall, .systemMedium]
  }

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: HomeWidgetSnapshot.kind, provider: Provider()) { entry in
      Content(entry: entry)
    }
    .configurationDisplayName("FINSIGHT")
    .description("진단 요약, 다음 진단일과 금융 습관 기록을 확인하세요.")
    .supportedFamilies(families)
  }
}

private enum EditorialKind {
  case news, action
}

private func editorialConfiguration(_ kind: EditorialKind) -> some WidgetConfiguration {
  let news = kind == .news
  return StaticConfiguration(kind: news ? HomeWidgetSnapshot.newsKind : HomeWidgetSnapshot.actionKind, provider: Provider()) { entry in
    Content(entry: entry, editorial: kind)
  }
  .configurationDisplayName(news ? "경제 뉴스" : "오늘의 행동")
  .description(news ? "오늘 편성된 경제 뉴스의 제목을 확인하세요." : "맞춤 가이드의 오늘의 행동을 확인하세요.")
  .supportedFamilies(news ? [.systemMedium] : [.systemSmall])
}

private struct FinsightNewsWidget: Widget {
  var body: some WidgetConfiguration { editorialConfiguration(.news) }
}

private struct FinsightActionWidget: Widget {
  var body: some WidgetConfiguration { editorialConfiguration(.action) }
}

@main
struct FinsightWidgetBundle: WidgetBundle {
  var body: some Widget {
    FinsightHomeWidget()
    FinsightNewsWidget()
    FinsightActionWidget()
  }
}
