import DailyCore
import DailyModels
import Foundation
import os

nonisolated extension Logger {
  static let agenda = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureAgenda")
}

/// One choice of the period picker (`RangeOption`, `lib/agendaWindow.ts:17-22`).
struct AgendaRange: Equatable, Hashable, Identifiable, Sendable {
  let days: Int
  let label: String
  /// How the empty state describes the period.
  let emptyLabel: String

  var id: Int { days }

  /// `AGENDA_RANGES`, `lib/agendaWindow.ts:27-33`.
  static let all: [AgendaRange] = [
    AgendaRange(days: 1, label: "Hoje", emptyLabel: "para hoje"),
    AgendaRange(days: 2, label: "Hoje e amanhã", emptyLabel: "para hoje e amanhã"),
    AgendaRange(days: 3, label: "3 dias", emptyLabel: "nos próximos 3 dias"),
    AgendaRange(days: 7, label: "7 dias", emptyLabel: "nos próximos 7 dias"),
    AgendaRange(days: 14, label: "14 dias", emptyLabel: "nos próximos 14 dias"),
  ]

  /// `agendaRange`: an unknown value falls back to "Hoje e amanhã", the default.
  static func range(for days: Int) -> AgendaRange {
    all.first { $0.days == days } ?? all[1]
  }

  /// The empty state's text (`components/AgendaPanel.tsx:144`).
  static func emptyText(days: Int) -> String {
    "Nada agendado \(range(for: days).emptyLabel)."
  }
}

/// The events of one day, in time order.
struct AgendaDayGroup: Equatable, Identifiable {
  let date: String
  let items: [AgendaItem]

  var id: String { date }
}

/// The pure rules of `components/AgendaPanel.tsx` and `lib/focusBlock.ts`.
enum AgendaLogic {
  static let weekdays = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
  static let months = [
    "janeiro", "fevereiro", "março", "abril", "maio", "junho",
    "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
  ]

  /// `groupByDate`: sorted by date then time, stable like `Array.prototype.sort`.
  static func group(_ items: [AgendaItem]) -> [AgendaDayGroup] {
    let sorted = items.enumerated()
      .sorted { lhs, rhs in
        if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
        if lhs.element.time != rhs.element.time { return lhs.element.time < rhs.element.time }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
    var groups: [AgendaDayGroup] = []
    for item in sorted {
      if let last = groups.last, last.date == item.date {
        groups[groups.count - 1] = AgendaDayGroup(date: last.date, items: last.items + [item])
      } else {
        groups.append(AgendaDayGroup(date: item.date, items: [item]))
      }
    }
    return groups
  }

  /// With a single calendar there is nothing to tell apart, so the label on
  /// every row would be noise (`AgendaPanel.tsx:85-87`).
  static func showsAccountLabels(_ items: [AgendaItem]) -> Bool {
    Set(items.map(\.account)).count > 1
  }

  /// `relativeDayLabel` (`AgendaPanel.tsx:56-67`): "hoje", "amanhã", or the
  /// weekday with the date spelled out.
  static func relativeDayLabel(_ iso: String, today: Date, calendar: Calendar) -> String {
    if iso == localDateString(today, calendar: calendar) { return "hoje" }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
      iso == localDateString(tomorrow, calendar: calendar)
    {
      return "amanhã"
    }
    let parts = iso.split(separator: "-").map { Int($0) }
    guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2],
      year != 0, (1...12).contains(month), day != 0,
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
    else { return iso }
    let weekday = calendar.component(.weekday, from: date)
    return "\(weekdays[weekday - 1]), \(day) de \(months[month - 1])"
  }

  static func localDateString(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// The first dropped item that `parseFocusSource` (`lib/focusBlock.ts:12-37`)
  /// would accept, trimmed like it. Anything else is ignored, as on the web.
  static func acceptedSource(_ items: [FocusSource]) -> FocusSource? {
    for item in items {
      let ref = item.ref.trimmingCharacters(in: .whitespacesAndNewlines)
      let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
      // JavaScript measures length in UTF-16 units.
      guard ref.utf16.count <= 64, !title.isEmpty, title.utf16.count <= 200 else { continue }
      if let url = item.url {
        guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "https", parsed.host() != nil else {
          continue
        }
      }
      return FocusSource(kind: item.kind, ref: ref, title: title, url: item.url)
    }
    return nil
  }

  /// `/api/integrations/agenda/google/start?login_hint=…` on the server: the
  /// Google flow runs in the browser, whose own session finishes it.
  static func reconnectURL(server: URL?, loginHint: String) -> URL? {
    guard let server, var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
    components.path = "/api/integrations/agenda/google/start"
    components.queryItems = loginHint.isEmpty ? nil : [URLQueryItem(name: "login_hint", value: loginHint)]
    return components.url
  }
}
