import DailyAPI
import DailyCore
import Foundation
import Testing

/// The Jira row labels shared by the Jira screen and "Hoje" (`lib/parsers/jira.ts`).
@Suite struct JiraFormatTests {
  @Test func normalizedStatus() {
    #expect(JiraFormat.normalizeStatus("  Em Andamento ") == "Em andamento")
    #expect(JiraFormat.normalizeStatus(" EM ANDAMENTO ") == "Em andamento")
    #expect(JiraFormat.normalizeStatus("") == "")
  }

  @Test func dueLabels() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 15)) ?? .now
    #expect(JiraFormat.dueLabel("2026-09-20", now: now, calendar: calendar) == "venceu há 2d")
    #expect(JiraFormat.dueLabel("2026-09-22", now: now, calendar: calendar) == "vence hoje")
    #expect(JiraFormat.dueLabel("2026-09-23", now: now, calendar: calendar) == "vence amanhã")
    #expect(JiraFormat.dueLabel("2026-09-25", now: now, calendar: calendar) == "vence em 3d")
    #expect(JiraFormat.dueLabel("2026-09-30", now: now, calendar: calendar) == "vence 30/09")
    #expect(JiraFormat.dueLabel("", now: now, calendar: calendar) == nil)
    #expect(JiraFormat.isOverdue("2026-09-21", now: now, calendar: calendar))
    #expect(!JiraFormat.isOverdue("2026-09-22", now: now, calendar: calendar))
  }

  @Test func staleness() {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let fresh = JSISODate.string(from: now.addingTimeInterval(-4.9 * 86_400))
    let old = JSISODate.string(from: now.addingTimeInterval(-6.5 * 86_400))
    #expect(JiraFormat.stalenessLabel(updatedAt: fresh, now: now) == nil)
    #expect(JiraFormat.stalenessLabel(updatedAt: old, now: now) == "parado há 6d")
    #expect(JiraFormat.stalenessLabel(updatedAt: "", now: now) == nil)
  }

  @Test func problemLabels() {
    #expect(JiraFormat.problemLabel(.storyWithoutEpic) == "sem épico")
    #expect(JiraFormat.problemLabel(.epicWithoutStories) == "sem histórias")
  }
}

/// `lib/filters.ts` (short) and `lib/format.ts` (named).
@Suite struct RelativeTimeTests {
  let now = Date(timeIntervalSince1970: 1_793_000_000)
  let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  @Test func shortFollowsTheFilterSteps() {
    let ago = { (seconds: TimeInterval) in RelativeTime.short(now.addingTimeInterval(-seconds), now: now, calendar: utc)
    }
    #expect(ago(30) == "agora")
    #expect(ago(12 * 60) == "12min")
    #expect(ago(3 * 3600) == "3h")
    #expect(ago(25 * 3600) == "ontem")
    #expect(ago(4 * 86_400) == "4d")
    let old = utc.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 15)) ?? now
    #expect(RelativeTime.short(old, now: now, calendar: utc) == "02/10")
  }

  @Test func namedFollowsTheWebSteps() {
    let parts = { (offset: TimeInterval) in RelativeTime.namedParts(now.addingTimeInterval(offset), now: now) }
    #expect(parts(-30) == (.second, -30))
    #expect(parts(-5 * 60) == (.minute, -5))
    #expect(parts(-3 * 3600) == (.hour, -3))
    #expect(parts(-86_400) == (.day, -1))
    #expect(parts(-14 * 86_400) == (.weekOfMonth, -2))
    #expect(parts(-400 * 86_400) == (.year, -1))
  }

  /// `Math.round(-2.5)` is -2 in JavaScript.
  @Test func namedRoundsHalvesUpLikeJavaScript() {
    #expect(RelativeTime.namedParts(now.addingTimeInterval(-150), now: now) == (.minute, -2))
  }

  @Test func namesYesterdayInPortuguese() {
    #expect(RelativeTime.named(now.addingTimeInterval(-86_400), now: now) == "ontem")
  }

  @Test func readsDatesWithoutMilliseconds() {
    #expect(RelativeTime.parseISO("2026-11-04T12:00:00Z") != nil)
    #expect(RelativeTime.parseISO("2026-11-04T12:00:00.123Z") != nil)
    #expect(RelativeTime.parseISO("ontem") == nil)
  }
}
