import DailyCore
import Foundation

/// Date reading and the short relative time, as the web does them
/// (`new Date(iso)` and `relativeTime` in `lib/filters.ts`).
nonisolated enum EmailDates {
  /// `Date.parse` for the ISO shapes the server writes. A date-time without
  /// a zone is local time and a date alone is UTC, as in JavaScript.
  static func parse(_ text: String, timeZone: TimeZone) -> Date? {
    let pattern =
      #/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?(Z|[+-]\d{2}:?\d{2})?)?$/#
    guard let match = text.trimmingCharacters(in: .whitespaces).wholeMatch(of: pattern) else { return nil }
    var components = DateComponents()
    components.year = Int(match.1)
    components.month = Int(match.2)
    components.day = Int(match.3)
    components.hour = match.4.flatMap { Int($0) } ?? 0
    components.minute = match.5.flatMap { Int($0) } ?? 0
    components.second = match.6.flatMap { Int($0) } ?? 0
    if let fraction = match.7 {
      let digits = String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
      components.nanosecond = (Int(digits) ?? 0) * 1_000_000
    }

    var calendar = Calendar(identifier: .gregorian)
    if match.4 == nil {
      calendar.timeZone = .gmt
    } else if let zone = match.8 {
      guard let offset = offsetSeconds(String(zone)), let fixed = TimeZone(secondsFromGMT: offset) else { return nil }
      calendar.timeZone = fixed
    } else {
      calendar.timeZone = timeZone
    }
    guard let date = calendar.date(from: components),
      calendar.component(.day, from: date) == components.day
    else { return nil }
    return date
  }

  private static func offsetSeconds(_ zone: String) -> Int? {
    if zone == "Z" { return 0 }
    let sign = zone.hasPrefix("-") ? -1 : 1
    let digits = zone.dropFirst().filter(\.isNumber)
    guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else {
      return nil
    }
    return sign * (hours * 3600 + minutes * 60)
  }

  /// "agora", "5min", "3h", "ontem", "4d", then "dd/MM"; empty when unreadable.
  static func relativeTime(_ iso: String, now: Date, timeZone: TimeZone) -> String {
    guard let then = parse(iso, timeZone: timeZone) else { return "" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return RelativeTime.short(then, now: now, calendar: calendar)
  }
}
