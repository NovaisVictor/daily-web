import Foundation

/// The web's two relative-time formats, shared by the screens that print them.
public nonisolated enum RelativeTime {
  /// `relativeTime` in `lib/filters.ts:23-43`: "agora", "12min", "3h", "ontem", "4d",
  /// then "dd/MM" in `calendar`'s time zone.
  public static func short(_ then: Date, now: Date, calendar: Calendar) -> String {
    let minutes = Int((now.timeIntervalSince(then) / 60).rounded(.down))
    if minutes < 1 { return "agora" }
    if minutes < 60 { return "\(minutes)min" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    if days == 1 { return "ontem" }
    if days < 7 { return "\(days)d" }
    let parts = calendar.dateComponents([.day, .month], from: then)
    return String(format: "%02d/%02d", parts.day ?? 0, parts.month ?? 0)
  }

  /// `RELATIVE_STEPS`, `lib/format.ts:29-37`.
  private static let steps: [(unit: Calendar.Component, span: Double)] = [
    (.second, 60), (.minute, 60), (.hour, 24), (.day, 7), (.weekOfMonth, 4.348), (.month, 12),
  ]

  /// The unit and signed amount `lib/format.ts` would print.
  public static func namedParts(_ date: Date, now: Date) -> (unit: Calendar.Component, amount: Int) {
    var delta = date.timeIntervalSince(now)
    for step in steps {
      if abs(delta) < step.span { return (step.unit, jsRound(delta)) }
      delta /= step.span
    }
    return (.year, jsRound(delta))
  }

  /// `relativeTime` in `lib/format.ts` (`Intl.RelativeTimeFormat`, `numeric: 'auto'`):
  /// "ontem", "agora" instead of "há 1 dia".
  public static func named(_ date: Date, now: Date, locale: Locale = Locale(identifier: "pt_BR")) -> String {
    let parts = namedParts(date, now: now)
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.dateTimeStyle = .named
    formatter.unitsStyle = .full
    var components = DateComponents()
    components.setValue(parts.amount, for: parts.unit)
    return formatter.localizedString(from: components)
  }

  /// `new Date(value)` for the ISO strings the server writes, with or without
  /// milliseconds. An unreadable date is an expected value (the web prints "—"),
  /// not a failure to report, hence `try?`.
  public static func parseISO(_ value: String) -> Date? {
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
