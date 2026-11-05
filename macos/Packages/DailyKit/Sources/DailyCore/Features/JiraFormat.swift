import DailyModels
import Foundation

/// The row labels of `lib/parsers/jira.ts` and `lib/parsers/jiraProblems.ts`, shared by
/// the Jira screen and the Jira panel of "Hoje".
public nonisolated enum JiraFormat {
  /// `normalizeStatus`, `lib/parsers/jira.ts:150-155`: "Em Andamento" and "Em
  /// andamento" read the same.
  public static func normalizeStatus(_ status: String) -> String {
    let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return "" }
    let lower = trimmed.lowercased(with: ptBR)
    return String(first).lowercased(with: ptBR).uppercased(with: ptBR) + lower.dropFirst()
  }

  private static let ptBR = Locale(identifier: "pt_BR")

  /// `STALE_AFTER_DAYS`, `lib/parsers/jira.ts:166`.
  public static let staleAfterDays = 5

  /// `stalenessLabel`, `lib/parsers/jira.ts:170-174`.
  public static func stalenessLabel(updatedAt: String, now: Date) -> String? {
    guard let updated = JiraDates.parse(updatedAt) else { return nil }
    let days = Int((now.timeIntervalSince(updated) / 86_400).rounded(.down))
    guard days >= staleAfterDays else { return nil }
    return "parado há \(days)d"
  }

  /// `dueLabel`, `lib/parsers/jira.ts:183-193`, counted in local days.
  public static func dueLabel(_ dueDate: String, now: Date, calendar: Calendar = .current) -> String? {
    guard let (year, month, day) = JiraDates.calendarParts(dueDate),
      let days = JiraDates.daysFromToday(year: year, month: month, day: day, now: now, calendar: calendar)
    else { return nil }
    if days < 0 { return "venceu há \(abs(days))d" }
    if days == 0 { return "vence hoje" }
    if days == 1 { return "vence amanhã" }
    if days <= 7 { return "vence em \(days)d" }
    return String(format: "vence %02d/%02d", day, month)
  }

  /// `isOverdue`, `lib/parsers/jira.ts:195-199`.
  public static func isOverdue(_ dueDate: String, now: Date, calendar: Calendar = .current) -> Bool {
    guard let (year, month, day) = JiraDates.calendarParts(dueDate),
      let days = JiraDates.daysFromToday(year: year, month: month, day: day, now: now, calendar: calendar)
    else { return false }
    return days < 0
  }

  /// `PROBLEM_LABEL`, `lib/parsers/jiraProblems.ts:68-74`.
  public static func problemLabel(_ problem: JiraProblem) -> String {
    switch problem {
    case .storyInProgressWithoutStart: "em andamento sem data de início"
    case .storyDoneWithoutStart: "concluída sem data de início"
    case .storyWithoutEpic: "sem épico"
    case .epicWithoutStories: "sem histórias"
    case .epicInProgressWithoutActiveStory: "em andamento sem história em andamento"
    default: problem.rawValue
    }
  }
}

/// `Date.parse` for the shapes the server sends: ISO 8601 with or without
/// milliseconds, and a bare `YYYY-MM-DD`, which JavaScript reads as UTC midnight.
public nonisolated enum JiraDates {
  public static func parse(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: value) { return date }
    guard let (year, month, day) = calendarParts(value) else { return nil }
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    return utc.date(from: DateComponents(year: year, month: month, day: day))
  }

  /// `YYYY-MM-DD` split into numbers; nil for anything else (the server sends
  /// `""` for "no date").
  public static func calendarParts(_ value: String) -> (Int, Int, Int)? {
    guard let match = value.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/),
      let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
      year > 0, month > 0, day > 0
    else { return nil }
    return (year, month, day)
  }

  /// Whole local days from today to the given date (negative in the past).
  public static func daysFromToday(year: Int, month: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
    return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day
  }

  /// `YYYY-MM-DD` of a local date.
  public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
    String(
      format: "%04d-%02d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date),
      calendar.component(.day, from: date))
  }

  /// The local date of a `YYYY-MM-DD`, for a date picker.
  public static func localDate(_ value: String, calendar: Calendar = .current) -> Date? {
    guard let (year, month, day) = calendarParts(value) else { return nil }
    return calendar.date(from: DateComponents(year: year, month: month, day: day))
  }
}
