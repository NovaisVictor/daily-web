/// A checklist item inside a task (`lib/types.ts:276-280`).
public struct SubTask: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var title: String
  public var completed: Bool

  public init(id: String, title: String, completed: Bool) {
    self.id = id
    self.title = title
    self.completed = completed
  }
}

/// `lib/types.ts:282`.
public struct TaskPriority: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let low = TaskPriority(rawValue: "low")
  public static let normal = TaskPriority(rawValue: "normal")
  public static let high = TaskPriority(rawValue: "high")
  public static let known: [TaskPriority] = [.low, .normal, .high]
}

/// The paper colour of a board note (`lib/types.ts:287`).
public struct NotePaper: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let yellow = NotePaper(rawValue: "yellow")
  public static let pink = NotePaper(rawValue: "pink")
  public static let blue = NotePaper(rawValue: "blue")
  public static let green = NotePaper(rawValue: "green")
  public static let white = NotePaper(rawValue: "white")
  public static let grey = NotePaper(rawValue: "grey")
  public static let known: [NotePaper] = [.yellow, .pink, .blue, .green, .white, .grey]
}

/// `lib/types.ts:289`.
public struct PinColor: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let red = PinColor(rawValue: "red")
  public static let blue = PinColor(rawValue: "blue")
  public static let yellow = PinColor(rawValue: "yellow")
  public static let green = PinColor(rawValue: "green")
  public static let known: [PinColor] = [.red, .blue, .yellow, .green]
}

/// `lib/types.ts:292`.
public struct PinShape: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let classic = PinShape(rawValue: "classic")
  public static let ball = PinShape(rawValue: "ball")
  public static let heart = PinShape(rawValue: "heart")
  public static let known: [PinShape] = [.classic, .ball, .heart]
}

/// A to-do (`lib/types.ts:294-315`). `due` and `time` are empty when unset;
/// `recur` is free text in the type (`''`, `none`, `daily`, `weekly`, `monthly`
/// in practice, `lib/operations/results.ts:12`), so it stays a `String`.
public struct TodoTask: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var title: String
  public var completed: Bool
  public var due: String
  public var priority: TaskPriority
  public var time: String
  public var recur: String
  public var notes: String
  public var subtasks: [SubTask]
  public var doing: Bool
  /// Null for the automatic colour.
  public var paper: NotePaper?
  public var pin: PinColor?
  /// Null for the classic pushpin.
  public var pinShape: PinShape?

  public init(
    id: String,
    title: String,
    completed: Bool,
    due: String,
    priority: TaskPriority,
    time: String,
    recur: String,
    notes: String,
    subtasks: [SubTask],
    doing: Bool,
    paper: NotePaper?,
    pin: PinColor?,
    pinShape: PinShape?
  ) {
    self.id = id
    self.title = title
    self.completed = completed
    self.due = due
    self.priority = priority
    self.time = time
    self.recur = recur
    self.notes = notes
    self.subtasks = subtasks
    self.doing = doing
    self.paper = paper
    self.pin = pin
    self.pinShape = pinShape
  }
}

/// `POST /api/tasks` (`app/api/tasks/route.ts:65`).
public struct CreatedTaskResponse: Codable, Sendable, Equatable, Hashable {
  public var id: String

  public init(id: String) {
    self.id = id
  }
}

/// `PATCH /api/tasks/{id}/board` (`app/api/tasks/[id]/board/route.ts:60,72`).
/// The saved style only comes back when the request changed it; inside it,
/// null means the automatic choice. Both read as `nil` here.
public struct TaskBoardResponse: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var paper: NotePaper?
  public var pin: PinColor?
  public var pinShape: PinShape?

  public init(ok: Bool, paper: NotePaper? = nil, pin: PinColor? = nil, pinShape: PinShape? = nil) {
    self.ok = ok
    self.paper = paper
    self.pin = pin
    self.pinShape = pinShape
  }
}
