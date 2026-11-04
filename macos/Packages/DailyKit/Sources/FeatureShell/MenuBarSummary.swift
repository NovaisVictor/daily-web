import DailyModels
import Foundation

/// What the menu bar item lists, read from the dashboard state the window already
/// polls: no request of its own.
public struct MenuBarSummary: Equatable, Sendable {
  public static let limit = 5

  public struct Event: Equatable, Identifiable, Sendable {
    public let id: Int
    /// "dia" for an all-day event, as `components/AgendaPanel.tsx:166-168`.
    public let time: String
    public let title: String
  }

  public struct DueTask: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let isOverdue: Bool
  }

  /// Today's events still ahead, all-day ones first; nil when the agenda is off.
  public let events: [Event]?
  public let agendaError: String?
  /// Late, then due today, open only; nil when tasks are off.
  public let tasks: [DueTask]?
  public let tasksError: String?
  public let unreadNotifications: Int

  public init(state: DashboardState, now: Date, calendar: Calendar = MenuBarSummary.calendar) {
    let today = Self.isoDay(now, calendar: calendar)
    let minute = Self.minuteOfDay(now, calendar: calendar)

    let agendaOn = state.modules.contains(.agenda)
    events = agendaOn ? state.agenda.data.map { Self.events($0, today: today, minute: minute) } : nil
    agendaError = agendaOn ? state.agenda.error : nil

    let tasksOn = state.modules.contains(.tasks)
    tasks = tasksOn ? state.tasks.data.map { Self.tasks($0, today: today) } : nil
    tasksError = tasksOn ? state.tasks.error : nil

    unreadNotifications = (state.notifications.data ?? []).count { !$0.read }
  }

  /// The same day boundary as the "Hoje" screen (`FeatureHome/HomeSummary.swift`),
  /// which a feature cannot share with another.
  static func events(_ items: [AgendaItem], today: String, minute: String) -> [Event] {
    // The web's sort (`components/AgendaPanel.tsx:34-37`): all-day ("") first.
    items.filter { $0.date == today }
      .sorted { $0.time < $1.time }
      .filter { $0.time.isEmpty || $0.time >= minute }
      .prefix(limit)
      .enumerated()
      .map { index, item in
        Event(
          id: index,
          time: item.time.isEmpty ? "dia" : item.time,
          title: item.title.isEmpty ? "—" : item.title
        )
      }
  }

  /// `isOverdue` and the "HOJE" group of `lib/taskGrouping.ts:29-33,77-79`, sorted by
  /// due date then priority (`lib/taskGrouping.ts:61-64`).
  static func tasks(_ items: [TodoTask], today: String) -> [DueTask] {
    let open = items.filter { !$0.completed && !$0.due.isEmpty && $0.due <= today }
    return open.sorted { a, b in
      if a.due != b.due { return a.due < b.due }
      return priorityRank(a.priority) < priorityRank(b.priority)
    }
    .prefix(limit)
    .map { DueTask(id: $0.id, title: $0.title, isOverdue: $0.due < today) }
  }

  private static func priorityRank(_ priority: TaskPriority) -> Int {
    switch priority {
    case .high: 0
    case .low: 2
    default: 1
    }
  }

  /// Gregorian in the local time zone, like JavaScript's `Date`.
  public static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  /// `YYYY-MM-DD`, the form task and agenda dates come in.
  static func isoDay(_ date: Date, calendar: Calendar) -> String {
    let c = { calendar.component($0, from: date) }
    return String(format: "%04d-%02d-%02d", c(.year), c(.month), c(.day))
  }

  /// `HH:MM`, the form agenda times come in.
  static func minuteOfDay(_ date: Date, calendar: Calendar) -> String {
    let c = { calendar.component($0, from: date) }
    return String(format: "%02d:%02d", c(.hour), c(.minute))
  }
}
