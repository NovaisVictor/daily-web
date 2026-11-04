import DailyModels
import Foundation

/// Small text and date helpers the Jira screen shares with the web
/// (`lib/filters.ts`, `lib/parsers/jira.ts`).
nonisolated enum JiraText {
  /// `matchesQuery`, `lib/filters.ts:14-18`: accent- and case-insensitive on both sides.
  static func matches(_ fields: [String], query: String) -> Bool {
    let term = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !term.isEmpty else { return true }
    return fields.contains { normalize($0).contains(term) }
  }

  static func normalize(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive], locale: nil).lowercased()
  }

  /// `String.prototype.localeCompare` in pt-BR, for the sorted option lists.
  static func localeLess(_ lhs: String, _ rhs: String) -> Bool {
    lhs.compare(rhs, locale: ptBR) == .orderedAscending
  }

  static let ptBR = Locale(identifier: "pt_BR")

  /// `isJiraKey`, `lib/jiraKey.ts`: letters, a hyphen, digits.
  static func isJiraKey(_ value: String) -> Bool {
    value.uppercased().wholeMatch(of: /[A-Z][A-Z0-9_]*-\d+/) != nil
  }

  /// `typeMarker`, `lib/parsers/jira.ts:3-17`.
  static func typeMarker(_ kind: String) -> String {
    typeMarkers[kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? "[?]"
  }

  static func issueMarker(_ item: JiraItem) -> String {
    item.subtask ? "[s]" : typeMarker(item.kind)
  }

  /// `isEpic`, `lib/parsers/jiraProblems.ts:16`: the same mapping that draws the marker.
  static func isEpic(_ item: JiraItem) -> Bool { issueMarker(item) == "[E]" }

  private static let typeMarkers: [String: String] = [
    "história": "[S]", "historia": "[S]", "story": "[S]",
    "epic": "[E]", "épico": "[E]", "epico": "[E]",
    "iniciativa": "[I]", "initiative": "[I]",
    "objetivo": "[O]", "objective": "[O]",
    "[system] service request": "[R]", "service request": "[R]",
    "solicitação de serviço": "[R]", "solicitacao de servico": "[R]",
    "pedido de serviço": "[R]", "pedido de servico": "[R]",
    "requisição": "[R]", "requisicao": "[R]",
  ]

  /// `normalizeStatus`, `lib/parsers/jira.ts:150-155`: "Em Andamento" and "Em
  /// andamento" read the same.
  static func normalizeStatus(_ status: String) -> String {
    let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return "" }
    let lower = trimmed.lowercased(with: ptBR)
    return String(first).lowercased(with: ptBR).uppercased(with: ptBR) + lower.dropFirst()
  }

  /// `STALE_AFTER_DAYS`, `lib/parsers/jira.ts:166`.
  static let staleAfterDays = 5

  /// `stalenessLabel`, `lib/parsers/jira.ts:170-174`.
  static func stalenessLabel(_ item: JiraItem, now: Date) -> String? {
    guard let updated = JiraDates.parse(item.updatedAt) else { return nil }
    let days = Int((now.timeIntervalSince(updated) / 86_400).rounded(.down))
    guard days >= staleAfterDays else { return nil }
    return "parado há \(days)d"
  }

  /// `dueLabel`, `lib/parsers/jira.ts:183-193`.
  static func dueLabel(_ dueDate: String, now: Date, calendar: Calendar = .current) -> String? {
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
  static func isOverdue(_ dueDate: String, now: Date, calendar: Calendar = .current) -> Bool {
    guard let (year, month, day) = JiraDates.calendarParts(dueDate),
      let days = JiraDates.daysFromToday(year: year, month: month, day: day, now: now, calendar: calendar)
    else { return false }
    return days < 0
  }

  /// `PROBLEM_LABEL`, `lib/parsers/jiraProblems.ts:68-74`.
  static func problemLabel(_ problem: JiraProblem) -> String {
    switch problem {
    case .storyInProgressWithoutStart: "em andamento sem data de início"
    case .storyDoneWithoutStart: "concluída sem data de início"
    case .storyWithoutEpic: "sem épico"
    case .epicWithoutStories: "sem histórias"
    case .epicInProgressWithoutActiveStory: "em andamento sem história em andamento"
    default: problem.rawValue
    }
  }

  /// `BASIS_NOTE`, `components/JiraProblemFix.tsx:13-17`.
  static func basisNote(_ basis: JiraStartDateBasis) -> String? {
    switch basis {
    case .started: "primeira passagem por andamento"
    case .finished: "foi do Backlog direto para concluída: dia da conclusão"
    case .created: "criada já fora do Backlog: dia da criação"
    default: nil
    }
  }

  /// `formatDate`, `components/jira/actions/EditActions.tsx:36-39`.
  static func formatDate(_ iso: String) -> String {
    guard let (year, month, day) = JiraDates.calendarParts(iso) else { return "sem prazo" }
    return String(format: "%02d/%02d/%04d", day, month, year)
  }
}

/// `Date.parse` for the shapes the server sends: ISO 8601 with or without
/// milliseconds, and a bare `YYYY-MM-DD`, which JavaScript reads as UTC midnight.
nonisolated enum JiraDates {
  static func parse(_ value: String) -> Date? {
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
  static func calendarParts(_ value: String) -> (Int, Int, Int)? {
    guard let match = value.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/),
      let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
      year > 0, month > 0, day > 0
    else { return nil }
    return (year, month, day)
  }

  /// Whole local days from today to the given date (negative in the past).
  static func daysFromToday(year: Int, month: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
    return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day
  }

  /// `YYYY-MM-DD` of a local date.
  static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
    String(
      format: "%04d-%02d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date),
      calendar.component(.day, from: date))
  }

  /// The local date of a `YYYY-MM-DD`, for a date picker.
  static func localDate(_ value: String, calendar: Calendar = .current) -> Date? {
    guard let (year, month, day) = calendarParts(value) else { return nil }
    return calendar.date(from: DateComponents(year: year, month: month, day: day))
  }
}
