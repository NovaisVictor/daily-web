import DailyModels
import Foundation

/// The day boundary and task order every screen shares: "Hoje", the menu bar,
/// the tasks list and the agenda must agree on what "today" and "late" mean.
///
/// The server's dates are `YYYY-MM-DD` and its times `HH:MM` on the Gregorian
/// calendar, like JavaScript's `Date`. A Buddhist or Japanese system calendar
/// numbers years differently, so only the given calendar's time zone is used.
public nonisolated enum TaskDay {
  /// Gregorian in `timeZone`.
  public static func gregorian(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  /// Gregorian in the current time zone, the default everywhere a day is read.
  public static var calendar: Calendar { gregorian(in: .current) }

  /// `YYYY-MM-DD` of the local day in `calendar`'s time zone
  /// (`toLocalDateString`, `lib/taskGrouping.ts:22-27`).
  public static func isoDay(_ date: Date, calendar: Calendar = TaskDay.calendar) -> String {
    let parts = gregorian(in: calendar.timeZone).dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// `HH:MM` in `calendar`'s time zone, the form agenda times come in.
  public static func minuteOfDay(_ date: Date, calendar: Calendar = TaskDay.calendar) -> String {
    let parts = gregorian(in: calendar.timeZone).dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }

  /// Day arithmetic on a `YYYY-MM-DD` string in UTC, as `addDays` does, so a
  /// daylight-saving change never moves a window edge.
  public static func addDays(_ iso: String, _ days: Int) -> String {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return iso }
    let utc = gregorian(in: .gmt)
    let start = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    guard let start, let shifted = utc.date(byAdding: .day, value: days, to: start) else { return iso }
    return isoDay(shifted, calendar: utc)
  }

  /// Unknown priorities sort with "normal": the web's rank table has no entry
  /// for them, and the middle is the least surprising place.
  public static func priorityRank(_ priority: TaskPriority) -> Int {
    switch priority {
    case .high: 0
    case .low: 2
    default: 1
    }
  }

  /// `lib/taskGrouping.ts:61-64` without the completed key: due date, then priority.
  public static func dueThenPriority(_ a: TodoTask, _ b: TodoTask) -> Bool {
    if a.due != b.due { return a.due < b.due }
    return priorityRank(a.priority) < priorityRank(b.priority)
  }

  /// Late and still open (`isOverdue`, `lib/taskGrouping.ts:29-33`).
  public static func isOverdue(_ task: TodoTask, today: String) -> Bool {
    !task.completed && !task.due.isEmpty && task.due < today
  }

  /// Open tasks late or due `today` (the "ATRASADAS" and "HOJE" groups,
  /// `lib/taskGrouping.ts:77-79`), each sorted by due date then priority.
  public static func dueByToday(_ tasks: [TodoTask], today: String) -> (overdue: [TodoTask], today: [TodoTask]) {
    let open = tasks.filter { !$0.completed && !$0.due.isEmpty }
    return (
      open.filter { $0.due < today }.sorted(by: dueThenPriority),
      open.filter { $0.due == today }.sorted(by: dueThenPriority)
    )
  }
}
