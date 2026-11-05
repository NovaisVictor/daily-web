import DailyCore
import DailyModels
import Foundation

/// The due-date windows of the list (`lib/taskGrouping.ts`).
nonisolated enum TaskGroupKey: String, CaseIterable, Sendable, Hashable {
  case overdue, today, week, month, later, noDate

  /// Upper case because they head the list; chips use `chipCase`.
  var label: String {
    switch self {
    case .overdue: "ATRASADAS"
    case .today: "HOJE"
    case .week: "ESTA SEMANA"
    case .month: "ESTE MÊS"
    case .later: "DEPOIS"
    case .noDate: "SEM DATA"
    }
  }

  /// Chip text: the band in sentence case (`chipCase`, `TasksPanel.tsx:99-102`).
  var chipLabel: String { TaskText.chipCase(label) }
}

nonisolated struct TaskGroup: Equatable, Sendable {
  let key: TaskGroupKey
  let tasks: [TodoTask]

  var label: String { key.label }
}

nonisolated enum TaskGrouping {
  /// `YYYY-MM-DD` of the person's own calendar day, like `toLocalDateString`;
  /// Gregorian whatever the system calendar is.
  static func localISO(_ date: Date, calendar: Calendar = TaskDay.calendar) -> String {
    TaskDay.isoDay(date, calendar: calendar)
  }

  static func addDays(_ iso: String, _ days: Int) -> String {
    TaskDay.addDays(iso, days)
  }

  /// `groupTasksByDueWindow`: empty windows are left out, each window lists
  /// open tasks first, then by due date, then by priority.
  static func group(_ tasks: [TodoTask], today: Date, calendar: Calendar = TaskDay.calendar) -> [TaskGroup] {
    let todayISO = localISO(today, calendar: calendar)
    let weekEnd = addDays(todayISO, 6)
    let monthEnd = addDays(todayISO, 29)
    var buckets: [TaskGroupKey: [TodoTask]] = [:]
    for task in tasks {
      buckets[key(of: task.due, today: todayISO, weekEnd: weekEnd, monthEnd: monthEnd), default: []].append(task)
    }
    return TaskGroupKey.allCases.compactMap { key in
      guard let list = buckets[key] else { return nil }
      return TaskGroup(key: key, tasks: sorted(list))
    }
  }

  /// Late and still open, with the same day boundary as "ATRASADAS".
  static func isOverdue(_ task: TodoTask, today: Date, calendar: Calendar = TaskDay.calendar) -> Bool {
    TaskDay.isOverdue(task, today: localISO(today, calendar: calendar))
  }

  private static func key(of due: String, today: String, weekEnd: String, monthEnd: String) -> TaskGroupKey {
    if due.isEmpty { return .noDate }
    if due < today { return .overdue }
    if due == today { return .today }
    if due <= weekEnd { return .week }
    if due <= monthEnd { return .month }
    return .later
  }

  /// Stable, like `Array.prototype.sort`.
  private static func sorted(_ list: [TodoTask]) -> [TodoTask] {
    list.enumerated()
      .sorted { lhs, rhs in
        let a = lhs.element
        let b = rhs.element
        if a.completed != b.completed { return !a.completed }
        if a.due != b.due { return a.due < b.due }
        let rankA = TaskDay.priorityRank(a.priority)
        let rankB = TaskDay.priorityRank(b.priority)
        if rankA != rankB { return rankA < rankB }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }
}

nonisolated enum TaskText {
  /// `formatDue`: the window already says which period, so only day/month and
  /// the time when there is one.
  static func formatDue(_ due: String, time: String) -> String {
    let parts = due.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count >= 3, !parts[1].isEmpty, !parts[2].isEmpty else { return due }
    let dayMonth = "\(parts[2])/\(parts[1])"
    return time.isEmpty ? dayMonth : "\(dayMonth) \(time)"
  }

  static func chipCase(_ label: String) -> String {
    let lower = label.lowercased(with: Locale(identifier: "pt_BR"))
    guard let first = lower.first else { return lower }
    return String(first).uppercased(with: Locale(identifier: "pt_BR")) + lower.dropFirst()
  }

  /// `matchesQuery` (`lib/filters.ts`): accent- and case-insensitive on both sides.
  static func matches(_ field: String, query: String) -> Bool {
    let term = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !term.isEmpty else { return true }
    return normalize(field).contains(term)
  }

  private static func normalize(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
  }

  static func priorityLabel(_ priority: TaskPriority) -> String {
    switch priority {
    case .high: "Alta"
    case .low: "Baixa"
    case .normal: "Normal"
    default: priority.rawValue
    }
  }
}
