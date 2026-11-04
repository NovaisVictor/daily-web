import DailyModels
import Foundation

/// The two lists of the panel (`ABAS` in `components/SlackPanel.tsx`).
nonisolated enum SlackTab: String, CaseIterable, Identifiable, Sendable {
  case mentions
  case directs

  var id: String { rawValue }

  var label: String {
    switch self {
    case .mentions: "Menções"
    case .directs: "Mensagens diretas"
    }
  }

  var emptyText: String {
    switch self {
    case .mentions: "Nenhuma menção nos últimos 7 dias."
    case .directs: "Nenhuma mensagem direta não lida."
    }
  }

  func items(in digest: SlackDigest?) -> [SlackMessage] {
    switch self {
    case .mentions: digest?.mentions ?? []
    case .directs: digest?.directs ?? []
    }
  }

  /// The tab that lists `id`; nil when neither does (the message left the digest).
  static func containing(_ id: String, in digest: SlackDigest?) -> SlackTab? {
    allCases.first { tab in tab.items(in: digest).contains { $0.id == id } }
  }
}

/// `formatRelative` (`lib/format.ts:39-49`): the same unit steps and rounding,
/// so the app and the web say "há 5 minutos" for the same message.
nonisolated enum SlackDates {
  static let emDash = "—"

  /// `RELATIVE_STEPS`, `lib/format.ts:29-37`.
  private static let steps: [(unit: Calendar.Component, span: Double)] = [
    (.second, 60), (.minute, 60), (.hour, 24), (.day, 7), (.weekOfMonth, 4.348), (.month, 12),
  ]

  /// The unit and signed amount the web would print; nil for a date it cannot read.
  static func relativeParts(_ value: String, now: Date) -> (unit: Calendar.Component, amount: Int)? {
    guard let date = parse(value) else { return nil }
    var delta = date.timeIntervalSince(now)
    for step in steps {
      if abs(delta) < step.span { return (step.unit, jsRound(delta)) }
      delta /= step.span
    }
    return (.year, jsRound(delta))
  }

  static func relative(_ value: String, now: Date, locale: Locale = Locale(identifier: "pt_BR")) -> String {
    guard let parts = relativeParts(value, now: now) else { return emDash }
    // `numeric: 'auto'` in the web: "ontem", "agora" instead of "há 1 dia".
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.dateTimeStyle = .named
    formatter.unitsStyle = .full
    var components = DateComponents()
    components.setValue(parts.amount, for: parts.unit)
    return formatter.localizedString(from: components)
  }

  /// `new Date(value)` for the ISO strings the server writes, with or without milliseconds.
  /// An unreadable date is an expected value here (the web prints "—"), not a
  /// failure to report, hence `try?`.
  static func parse(_ value: String) -> Date? {
    if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
      return date
    }
    return try? Date(value, strategy: Date.ISO8601FormatStyle())
  }

  /// `Math.round`: halves go up, also for negatives (-2.5 → -2).
  private static func jsRound(_ value: Double) -> Int {
    Int((value + 0.5).rounded(.down))
  }
}
