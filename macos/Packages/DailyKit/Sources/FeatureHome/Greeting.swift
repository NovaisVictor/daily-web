import DailyCore
import DailyModels
import Foundation

/// Whether this is the person's first sign-in or a later one (`lib/greeting.ts:2`).
enum WelcomeKind: Equatable, Sendable {
  case first
  case returning

  /// `WELCOME_LABELS` in `lib/greeting.ts:4-7`.
  var label: String {
    switch self {
    case .first: "Bem-vindo"
    case .returning: "Bem-vindo de volta"
    }
  }
}

/// The heading and the line under it in `components/NowBand.tsx:18-20`. The web has
/// no time-of-day rule: it always says "Olá" and picks the welcome by sign-in count.
struct Greeting: Equatable, Sendable {
  var heading: String
  var welcome: String

  init(user: CurrentUser?, welcome: WelcomeKind) {
    let name = user.map { Self.greetingName(fullName: $0.fullName, username: $0.username) }
    heading = name.map { "Olá, \($0)" } ?? "Olá"
    self.welcome = welcome.label
  }

  /// The first name when the profile has a full name, the username otherwise
  /// (`greetingName` in `lib/greeting.ts:10-12`).
  static func greetingName(fullName: String?, username: String) -> String {
    let first = fullName?.split(whereSeparator: \.isWhitespace).first.map(String.init)
    guard let first, !first.isEmpty else { return username }
    return first
  }
}

/// The two lines of `components/Clock.tsx`: `HH:MM:SS` and "quarta-feira, 4 de novembro".
enum ClockText {
  /// Indexed like JavaScript's `getDay()` (0 = Sunday); `Calendar.weekday` is 1-based.
  static let weekdays = [
    "domingo", "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado",
  ]
  static let months = [
    "janeiro", "fevereiro", "março", "abril", "maio", "junho",
    "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
  ]

  /// Gregorian in the local time zone, like JavaScript's `Date`: the name tables
  /// above assume seven weekdays and twelve months, which other calendars break.
  static var calendar: Calendar { TaskDay.calendar }

  static func time(_ date: Date, calendar: Calendar = ClockText.calendar) -> String {
    let c = { calendar.component($0, from: date) }
    return String(format: "%02d:%02d:%02d", c(.hour), c(.minute), c(.second))
  }

  static func date(_ date: Date, calendar: Calendar = ClockText.calendar) -> String {
    let c = { calendar.component($0, from: date) }
    return "\(weekdays[c(.weekday) - 1]), \(c(.day)) de \(months[c(.month) - 1])"
  }

  /// `YYYY-MM-DD` in local time, the form task and agenda dates come in
  /// (`toLocalDateString` in `lib/taskGrouping.ts:22-27`).
  static func isoDay(_ date: Date, calendar: Calendar = ClockText.calendar) -> String {
    TaskDay.isoDay(date, calendar: calendar)
  }

  /// `HH:MM` in local time, the form agenda times come in.
  static func minuteOfDay(_ date: Date, calendar: Calendar = ClockText.calendar) -> String {
    TaskDay.minuteOfDay(date, calendar: calendar)
  }
}
