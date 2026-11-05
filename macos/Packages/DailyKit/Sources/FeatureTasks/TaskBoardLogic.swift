import DailyModels
import Foundation

/// A column of the board (`lib/taskBoard.ts`).
nonisolated enum BoardColumn: String, CaseIterable, Sendable, Hashable, Identifiable {
  case todo, doing, done

  var id: String { rawValue }

  var label: String {
    switch self {
    case .todo: "A fazer"
    case .doing: "Fazendo"
    case .done: "Feito"
    }
  }

  /// The columns either side, for the keyboard move buttons.
  var neighbours: (previous: BoardColumn?, next: BoardColumn?) {
    let all = Self.allCases
    guard let index = all.firstIndex(of: self) else { return (nil, nil) }
    return (index > 0 ? all[index - 1] : nil, index < all.count - 1 ? all[index + 1] : nil)
  }
}

/// One request a move needs.
nonisolated enum MoveStep: Equatable, Sendable {
  case complete(Bool)
  case status(BoardColumn)
}

/// The note's look, as the board route takes it: a key left out keeps its
/// value, and `.some(nil)` goes back to automatic.
nonisolated struct NoteStylePatch: Equatable, Sendable {
  var paper: NotePaper??
  var pin: PinColor??
  var pinShape: PinShape??

  init(paper: NotePaper?? = .none, pin: PinColor?? = .none, pinShape: PinShape?? = .none) {
    self.paper = paper
    self.pin = pin
    self.pinShape = pinShape
  }

  /// All three keys, as the form saves them.
  static func full(paper: NotePaper?, pin: PinColor?, pinShape: PinShape?) -> NoteStylePatch {
    NoteStylePatch(paper: .some(paper), pin: .some(pin), pinShape: .some(pinShape))
  }

  func applied(to task: TodoTask) -> TodoTask {
    var next = task
    if case .some(let value) = paper { next.paper = value }
    if case .some(let value) = pin { next.pin = value }
    if case .some(let value) = pinShape { next.pinShape = value }
    return next
  }

  /// The task's current values for the same keys, to put back on failure.
  func previous(in task: TodoTask) -> NoteStylePatch {
    NoteStylePatch(
      paper: paper == nil ? .none : .some(task.paper),
      pin: pin == nil ? .none : .some(task.pin),
      pinShape: pinShape == nil ? .none : .some(task.pinShape)
    )
  }

  /// `describeStyle` in `TasksPanel.tsx`, for the announcement.
  var description: String {
    if case .some(let value) = paper {
      return value.map { "Papel \(TaskBoard.paperLabel($0))" } ?? "Papel automático"
    }
    if case .some(let value) = pinShape {
      return "Alfinete \(TaskBoard.shapeLabel(value ?? .classic))"
    }
    if case .some(.some(let value)) = pin { return "Alfinete \(TaskBoard.pinLabel(value))" }
    return "Alfinete automático"
  }
}

nonisolated enum TaskBoard {
  /// "Feito" only grows; past this many notes the rest hide behind a button.
  static let doneLimit = 10

  /// Completed wins over "doing": the overlay may outlive a completion made elsewhere.
  static func column(of task: TodoTask) -> BoardColumn {
    if task.completed { return .done }
    return task.doing ? .doing : .todo
  }

  /// Keeps the order the tasks came in.
  static func byColumn(_ tasks: [TodoTask]) -> [BoardColumn: [TodoTask]] {
    var columns: [BoardColumn: [TodoTask]] = [.todo: [], .doing: [], .done: []]
    for task in tasks { columns[column(of: task), default: []].append(task) }
    return columns
  }

  /// `planMove`: leaving "Feito" reopens first; entering it completes.
  static func planMove(_ task: TodoTask, to: BoardColumn) -> [MoveStep] {
    let from = column(of: task)
    if from == to { return [] }
    if to == .done { return [.complete(true)] }
    var steps: [MoveStep] = []
    if from == .done { steps.append(.complete(false)) }
    steps.append(.status(to))
    return steps
  }

  /// `idHash`: the JavaScript 32-bit string hash over UTF-16 units.
  static func idHash(_ id: String) -> Int {
    var hash: Int32 = 0
    for unit in id.utf16 { hash = hash &* 31 &+ Int32(unit) }
    return Int(Int64(hash).magnitude)
  }

  /// Between -2 and 2 degrees, the same for a task every time.
  static func tilt(_ id: String) -> Double {
    let steps = Double(idHash(id) % 41)
    return ((steps / 10 - 2) * 10).rounded() / 10
  }

  /// `noteCurls`: about one note in three has its bottom corner peeling off
  /// the board (`lib/taskBoard.ts:156-158`).
  static func curls(_ id: String) -> Bool {
    (idHash(id) / 3) % 3 == 0
  }

  static let papers: [NotePaper] = [.yellow, .pink, .blue, .green, .white, .grey]
  static let pins: [PinColor] = [.red, .blue, .yellow, .green]
  static let shapes: [PinShape] = [.classic, .ball, .heart]

  static func derivedPaper(completed: Bool, priority: TaskPriority) -> NotePaper {
    if completed { return .green }
    if priority == .high { return .pink }
    if priority == .low { return .blue }
    return .yellow
  }

  /// A chosen paper wins even over the green of a finished note.
  static func paper(of task: TodoTask) -> NotePaper {
    task.paper ?? derivedPaper(completed: task.completed, priority: task.priority)
  }

  static func clashes(_ pin: PinColor, on paper: NotePaper) -> Bool {
    switch paper {
    case .yellow, .white, .grey: pin == .yellow
    case .pink: pin == .red
    case .blue: pin == .blue
    case .green: pin == .green
    default: false
    }
  }

  /// Varied across the board, but never the colour the paper would hide.
  static func pin(of task: TodoTask) -> PinColor {
    if let pin = task.pin { return pin }
    let paper = paper(of: task)
    let options = pins.filter { !clashes($0, on: paper) }
    return options[(idHash(task.id) / 7) % options.count]
  }

  static func pinShape(of task: TodoTask) -> PinShape {
    task.pinShape ?? .classic
  }

  static func paperLabel(_ paper: NotePaper) -> String {
    switch paper {
    case .yellow: "amarelo"
    case .pink: "rosa"
    case .blue: "azul"
    case .green: "verde"
    case .white: "branco"
    case .grey: "cinza"
    default: paper.rawValue
    }
  }

  static func pinLabel(_ pin: PinColor) -> String {
    switch pin {
    case .red: "vermelho"
    case .blue: "azul"
    case .yellow: "amarelo"
    case .green: "verde"
    default: pin.rawValue
    }
  }

  static func shapeLabel(_ shape: PinShape) -> String {
    switch shape {
    case .classic: "clássico"
    case .ball: "bolinha"
    case .heart: "coração"
    default: shape.rawValue
    }
  }
}

/// The narrow board (`TaskBoard.tsx:393-421`): below `@[30rem]` one column
/// shows at a time, behind tabs, because stacked lanes put "Fazendo" and
/// "Feito" far below the fold of a panel.
nonisolated enum BoardTabs {
  /// `30rem`.
  static let breakpoint: CGFloat = 480

  static func usesTabs(width: CGFloat) -> Bool {
    width < breakpoint
  }

  /// The lanes drawn at `width`: all three, or the active tab's alone.
  static func columns(width: CGFloat, active: BoardColumn) -> [BoardColumn] {
    usesTabs(width: width) ? [active] : BoardColumn.allCases
  }

  /// The tab once a move by button or keys ended: the note's new lane when
  /// the server took the move, so the focus can follow it; else the tab the
  /// note is still in. Switching before the answer would leave a refused move
  /// on a tab without the note.
  static func tab(afterMoveTo column: BoardColumn, moved: Bool, current: BoardColumn) -> BoardColumn {
    moved ? column : current
  }
}
