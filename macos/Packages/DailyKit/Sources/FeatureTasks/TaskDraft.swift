import DailyCore
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

/// What the task form edits, with the web form's state (`TaskFormModal.tsx:114-133`):
/// the date is a day and a time, and the free text ("amanhã 14:30") is only a way
/// of typing them, behind "Digitar data". What is sent is the parsed
/// `YYYY-MM-DD [HH:MM]`, never the text (`TaskFormModal.tsx:224`).
nonisolated struct TaskDraft: Equatable, Sendable {
  /// `TITLE_MAX`, the input's `maxLength` (UTF-16 units, as the browser counts).
  static let titleLimit = 255
  static let priorities: [TaskPriority] = [.high, .normal, .low]

  var title: String
  /// `YYYY-MM-DD`, or empty for "Sem data".
  private(set) var day: String
  /// `HH:MM`, or empty for "Sem hora"; always empty without a day.
  private(set) var time: String
  /// The "Digitar data" text; it only moves `day` and `time` while it parses.
  private(set) var typed = ""
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
    title = task?.title ?? ""
    self.day = day
    time = task.map(\.time).flatMap { !day.isEmpty && Self.isTime($0) ? $0 : nil } ?? ""
    recur = day.isEmpty ? .none : TaskRecur(stored: task?.recur ?? "")
    priority = task?.priority ?? .normal
    paper = task?.paper
    pin = task?.pin
    pinShape = task?.pinShape
    column = task.map { TaskBoard.column(of: $0) } ?? .todo
  }

  var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  var hasDue: Bool { !day.isEmpty }

  /// The `due` the web sends: `day`, or `day time`, or empty.
  var due: String {
    guard hasDue else { return "" }
    return time.isEmpty ? day : "\(day) \(time)"
  }

  /// A recurring task without a date would be completed for good, so the
  /// recurrence only counts while there is a date.
  var effectiveRecur: TaskRecur { hasDue ? recur : .none }

  var style: NoteStylePatch { .full(paper: paper, pin: pin, pinShape: pinShape) }

  func styleChanged(from initial: TaskDraft) -> Bool {
    paper != initial.paper || pin != initial.pin || pinShape != initial.pinShape
  }

  /// Whether closing would throw something away; typed text counts even when
  /// it does not parse, as on the web.
  func isDirty(comparedTo initial: TaskDraft) -> Bool {
    styleChanged(from: initial) || title != initial.title || day != initial.day || time != initial.time
      || effectiveRecur != initial.effectiveRecur || priority != initial.priority || column != initial.column
      || !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// A quick chip or the "Dia" picker. A time without a day means nothing to
  /// the API, so it goes with the day.
  mutating func setDay(_ iso: String?) {
    day = iso ?? ""
    if day.isEmpty { time = "" }
  }

  /// The "Hora" picker; a time needs a day, as the web's disabled input does.
  mutating func setTime(_ value: String?) {
    guard hasDue else { return }
    time = value ?? ""
  }

  /// `onTypedChange`: while the text does not parse, the day and time keep
  /// their last valid value and the hint says what is wrong.
  mutating func setTyped(_ value: String, now: Date, calendar: Calendar = TaskDay.calendar) {
    typed = value
    if let parsed = Self.tryParse(value, now: now, calendar: calendar) {
      day = parsed.day
      time = parsed.time
    }
  }

  /// Closing "Digitar data" drops the text, not the date it set.
  mutating func clearTyped() {
    typed = ""
  }

  /// `typedError`: typed text that does not parse blocks "Salvar".
  func typedIsInvalid(now: Date, calendar: Calendar = TaskDay.calendar) -> Bool {
    let value = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    return !value.isEmpty && Self.tryParse(value, now: now, calendar: calendar) == nil
  }

  /// The line under the typed field (`TaskFormModal.tsx:160-165`, `:431-432`):
  /// the preview, the refusal, or the examples while empty.
  func typedHint(now: Date, calendar: Calendar = TaskDay.calendar) -> (text: String, isError: Bool) {
    let value = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return ("hoje, amanhã, +3d ou AAAA-MM-DD, com hora opcional no fim", false) }
    if let preview = DueDateParser.preview(value, now: now, calendar: calendar) { return ("→ \(preview)", false) }
    return ("Não reconheci \"\(value)\". Exemplos: hoje, amanhã 14:30, +3d, 2026-11-05 09:00.", true)
  }

  /// `tryParseDue`: the day and time of the text, or nil while it does not parse.
  private static func tryParse(_ value: String, now: Date, calendar: Calendar) -> (day: String, time: String)? {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    do {
      let parsed = try DueDateParser.parse(value, now: now, calendar: calendar)
      return (parsed.due, parsed.time == "none" ? "" : parsed.time)
    } catch {
      // Being typed: not parsing yet is expected, and `typedHint` says why.
      return nil
    }
  }

  /// `title` cut to `titleLimit` UTF-16 units, as the browser's `maxLength`
  /// counts, without splitting a character (an emoji counts two or more).
  static func clipped(_ title: String) -> String {
    guard title.utf16.count > titleLimit else { return title }
    var clipped = ""
    for character in title {
      guard clipped.utf16.count + String(character).utf16.count <= titleLimit else { break }
      clipped.append(character)
    }
    return clipped
  }

  /// Whether the title still is what the last cut at `titleLimit` left (`cutTitle`):
  /// the hint shows after a cut and goes as soon as the text is edited again.
  static func showsLimitHint(title: String, cutTitle: String?) -> Bool {
    cutTitle == title
  }

  /// `POST /api/tasks` from the form. `status` only for "Fazendo": the
  /// server's default is "A fazer".
  var createBody: TasksEndpoints.CreateBody {
    TasksEndpoints.CreateBody(
      title: trimmedTitle,
      due: due,
      priority: priority,
      recur: effectiveRecur == .none ? nil : effectiveRecur.rawValue,
      status: column == .doing ? BoardColumn.doing.rawValue : nil
    )
  }

  var editBody: TasksEndpoints.EditBody {
    TasksEndpoints.EditBody(
      title: trimmedTitle, due: due, priority: priority, recur: effectiveRecur.rawValue)
  }

  /// Dates for the chips "Hoje", "Amanhã" and "Próx. semana" (the coming Monday).
  static func quickDays(now: Date, calendar: Calendar = TaskDay.calendar)
    -> (today: String, tomorrow: String, monday: String)
  {
    let calendar = TaskDay.gregorian(in: calendar.timeZone)
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
    value.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}/) != nil
  }

  private static func isTime(_ value: String) -> Bool {
    value.wholeMatch(of: /[0-9]{2}:[0-9]{2}/) != nil
  }
}
