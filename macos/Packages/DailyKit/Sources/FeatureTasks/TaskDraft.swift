import DailyModels
import Foundation

/// `RECUR_OPTIONS` of `TaskFormModal.tsx`.
nonisolated enum TaskRecur: String, CaseIterable, Sendable, Identifiable {
  case none, daily, weekly, monthly

  var id: String { rawValue }

  var label: String {
    switch self {
    case .none: "Não repete"
    case .daily: "Diária"
    case .weekly: "Semanal"
    case .monthly: "Mensal"
    }
  }

  /// The local store writes `monthly` and Microsoft To Do reports
  /// `absoluteMonthly`; both open as "Mensal" (`initialRecur`).
  init(stored: String) {
    switch stored {
    case "daily": self = .daily
    case "weekly": self = .weekly
    case "monthly", "absoluteMonthly": self = .monthly
    default: self = .none
    }
  }
}

/// What the task form edits. The due date is free text the server parses
/// (`lib/dateParsing.ts`): "hoje", "amanhã 14:30", "+3d", "2026-11-05 09:00".
nonisolated struct TaskDraft: Equatable, Sendable {
  /// `TITLE_MAX`, the input's `maxLength` (UTF-16 units, as the browser counts).
  static let titleLimit = 255
  static let priorities: [TaskPriority] = [.high, .normal, .low]

  var title: String
  var dueText: String
  var recur: TaskRecur
  var priority: TaskPriority
  var paper: NotePaper?
  var pin: PinColor?
  var pinShape: PinShape?
  /// Where a new task starts on the board; ignored when editing.
  var column: BoardColumn

  /// A stored date only counts when it has the shape the server writes;
  /// anything else opens as "no date", and a recurrence without a date as
  /// "Não repete" (`TaskFormModal.tsx:110-122`).
  init(task: TodoTask?) {
    let day = task.map(\.due).flatMap { Self.isISODay($0) ? $0 : nil } ?? ""
    let time = task.map(\.time).flatMap { !day.isEmpty && Self.isTime($0) ? $0 : nil } ?? ""
    title = task?.title ?? ""
    dueText = time.isEmpty ? day : "\(day) \(time)"
    recur = day.isEmpty ? .none : TaskRecur(stored: task?.recur ?? "")
    priority = task?.priority ?? .normal
    paper = task?.paper
    pin = task?.pin
    pinShape = task?.pinShape
    column = task.map { TaskBoard.column(of: $0) } ?? .todo
  }

  var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  var trimmedDue: String { dueText.trimmingCharacters(in: .whitespacesAndNewlines) }
  var hasDue: Bool { !trimmedDue.isEmpty }

  /// A recurring task without a date would be completed for good, so the
  /// recurrence only counts while there is a date.
  var effectiveRecur: TaskRecur { hasDue ? recur : .none }

  var style: NoteStylePatch { .full(paper: paper, pin: pin, pinShape: pinShape) }

  func styleChanged(from initial: TaskDraft) -> Bool {
    paper != initial.paper || pin != initial.pin || pinShape != initial.pinShape
  }

  /// Whether closing would throw something away.
  func isDirty(comparedTo initial: TaskDraft) -> Bool {
    styleChanged(from: initial) || title != initial.title || dueText != initial.dueText
      || effectiveRecur != initial.effectiveRecur || priority != initial.priority || column != initial.column
  }

  /// The first word of the date text, the day.
  var dayPart: String {
    trimmedDue.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
  }

  /// A quick date chip: replaces the day and keeps a typed time; no day
  /// clears the time too, which means nothing without a day.
  mutating func setDay(_ iso: String?) {
    guard let iso else {
      dueText = ""
      return
    }
    let words = trimmedDue.split(whereSeparator: \.isWhitespace).map(String.init)
    dueText = words.count > 1 ? "\(iso) \(words[1])" : iso
  }

  /// Clips the title to the browser's `maxLength`.
  mutating func clipTitle() {
    guard title.utf16.count > Self.titleLimit else { return }
    var clipped = ""
    for character in title {
      guard clipped.utf16.count + String(character).utf16.count <= Self.titleLimit else { break }
      clipped.append(character)
    }
    title = clipped
  }

  /// `POST /api/tasks` from the form. `status` only for "Fazendo": the
  /// server's default is "A fazer".
  var createBody: TasksEndpoints.CreateBody {
    TasksEndpoints.CreateBody(
      title: trimmedTitle,
      due: trimmedDue,
      priority: priority,
      recur: effectiveRecur == .none ? nil : effectiveRecur.rawValue,
      status: column == .doing ? BoardColumn.doing.rawValue : nil
    )
  }

  var editBody: TasksEndpoints.EditBody {
    TasksEndpoints.EditBody(
      title: trimmedTitle, due: trimmedDue, priority: priority, recur: effectiveRecur.rawValue)
  }

  /// Dates for the chips "Hoje", "Amanhã" and "Próx. semana" (the coming Monday).
  static func quickDays(now: Date, calendar: Calendar = .current) -> (today: String, tomorrow: String, monday: String) {
    let today = calendar.startOfDay(for: now)
    let weekday = calendar.component(.weekday, from: today)
    // `((8 - getDay()) % 7) || 7`, with Sunday = 1 in Foundation and 0 in JS.
    let untilMonday = (8 - (weekday - 1)) % 7 == 0 ? 7 : (8 - (weekday - 1)) % 7
    func shifted(_ days: Int) -> String {
      TaskGrouping.localISO(calendar.date(byAdding: .day, value: days, to: today) ?? today, calendar: calendar)
    }
    return (TaskGrouping.localISO(today, calendar: calendar), shifted(1), shifted(untilMonday))
  }

  private static func isISODay(_ value: String) -> Bool {
    value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
  }

  private static func isTime(_ value: String) -> Bool {
    value.wholeMatch(of: /\d{2}:\d{2}/) != nil
  }
}
