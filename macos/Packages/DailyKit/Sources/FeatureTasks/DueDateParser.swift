import DailyCore
import Foundation

/// `ParsedDue` (`lib/dateParsing.ts`): `none` means "no date" / "no time".
nonisolated struct ParsedDue: Equatable, Sendable {
  var due: String
  var time: String
}

/// The parser's refusal, with the server's own words.
nonisolated struct DueParseError: Error, Equatable, Sendable {
  var message: String
}

/// `parseDueInput` (`lib/dateParsing.ts`), line by line. The server parses the
/// text again on save; the form uses this copy for the live preview, like the
/// web's `TaskFormModal`.
nonisolated enum DueDateParser {
  /// Only `calendar`'s time zone counts: the days are always Gregorian.
  static func parse(_ input: String, now: Date, calendar: Calendar = TaskDay.calendar) throws(DueParseError)
    -> ParsedDue
  {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return ParsedDue(due: "none", time: "none") }

    let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    let datePart = parts[0].lowercased()
    let timePart = parts.count > 1 ? parts[1] : nil

    let due: String
    if datePart == "hoje" {
      due = TaskGrouping.localISO(now, calendar: calendar)
    } else if datePart == "amanhã" || datePart == "amanha" {
      due = TaskGrouping.localISO(shifted(now, days: 1), calendar: calendar)
    } else if let match = datePart.wholeMatch(of: /\+([0-9]+)d/), let days = Int(match.1) {
      due = TaskGrouping.localISO(shifted(now, days: days), calendar: calendar)
    } else {
      guard let match = datePart.wholeMatch(of: /([0-9]{4})-([0-9]{2})-([0-9]{2})/),
        let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
        isValidDate(year: year, month: month, day: day)
      else { throw DueParseError(message: "data inválida: \(parts[0])") }
      due = datePart
    }

    guard let timePart else { return ParsedDue(due: due, time: "none") }
    guard timePart.wholeMatch(of: /([01][0-9]|2[0-3]):([0-5][0-9])/) != nil else {
      throw DueParseError(message: "hora inválida: \(timePart) — use HH:MM")
    }
    return ParsedDue(due: due, time: timePart)
  }

  /// `tryParseDue` + `describeDue` of `TaskFormModal.tsx`: "qua, 05/11 14:30",
  /// or nil for text that does not parse or is empty.
  static func preview(_ input: String, now: Date, calendar: Calendar = TaskDay.calendar) -> String? {
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let parsed: ParsedDue
    do {
      parsed = try parse(input, now: now, calendar: calendar)
    } catch {
      // A field being typed: not parsing yet is expected, the caller shows the hint.
      return nil
    }
    return describe(day: parsed.due, time: parsed.time == "none" ? "" : parsed.time, calendar: calendar)
  }

  /// `WEEKDAYS` (`TaskFormModal.tsx:48`).
  static let weekdays = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]

  static func describe(day: String, time: String, calendar: Calendar = TaskDay.calendar) -> String? {
    let calendar = TaskDay.gregorian(in: calendar.timeZone)
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3,
      let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    else { return nil }
    let weekday = weekdays[calendar.component(.weekday, from: date) - 1]
    let label = "\(weekday), " + String(format: "%02d/%02d", parts[2], parts[1])
    return time.isEmpty ? label : "\(label) \(time)"
  }

  /// `setUTCDate(getUTCDate() + n)`: whole days of 24 h, as the web adds them.
  private static func shifted(_ date: Date, days: Int) -> Date {
    date.addingTimeInterval(Double(days) * 86_400)
  }

  private static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
    let utc = TaskDay.gregorian(in: .gmt)
    guard (1...12).contains(month), (1...31).contains(day),
      let date = utc.date(from: DateComponents(year: year, month: month, day: day))
    else { return false }
    let back = utc.dateComponents([.year, .month, .day], from: date)
    return back.year == year && back.month == month && back.day == day
  }
}
