/// A mailbox the user connected, for filters and replies (`lib/types.ts:398-401`).
public struct MailboxRef: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var label: String

  public init(id: String, label: String) {
    self.id = id
    self.label = label
  }
}

/// A calendar the agenda reads, and whether focus blocks can be written to it
/// (`lib/types.ts:74-79`).
public struct AgendaCalendarRef: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var label: String
  public var account: String
  public var canWrite: Bool

  public init(id: String, label: String, account: String, canWrite: Bool) {
    self.id = id
    self.label = label
    self.account = account
    self.canWrite = canWrite
  }
}

/// One agenda entry (`lib/types.ts:66-72`). `time` is empty for all-day events.
public struct AgendaItem: Codable, Sendable, Equatable, Hashable {
  public var account: String
  public var accountLabel: String
  public var date: String
  public var time: String
  public var title: String

  public init(account: String, accountLabel: String, date: String, time: String, title: String) {
    self.account = account
    self.accountLabel = accountLabel
    self.date = date
    self.time = time
    self.title = title
  }
}

/// `POST /api/agenda/focus-blocks`, status 201 (`app/api/agenda/focus-blocks/route.ts:98`).
public struct FocusBlockResponse: Codable, Sendable, Equatable, Hashable {
  public var item: AgendaItem

  public init(item: AgendaItem) {
    self.item = item
  }
}

/// How the tasks panel is laid out (`lib/types.ts:321`).
public struct TasksView: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let list = TasksView(rawValue: "list")
  public static let board = TasksView(rawValue: "board")
  public static let known: [TasksView] = [.list, .board]
}

/// How the web home page arranges panels (`lib/types.ts:323`). The app ignores it.
public struct HomeView: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let grid = HomeView(rawValue: "grid")
  public static let workspace = HomeView(rawValue: "workspace")
  public static let known: [HomeView] = [.grid, .workspace]
}

/// One tile of the web grid layout (`lib/types.ts:433`). The app ignores it.
public struct LayoutItem: Codable, Sendable, Equatable, Hashable {
  public var i: String
  public var x: Double
  public var y: Double
  public var w: Double
  public var h: Double

  public init(i: String, x: Double, y: Double, w: Double, h: Double) {
    self.i = i
    self.x = x
    self.y = y
    self.w = w
    self.h = h
  }
}

/// A web grid layout saved for one window size (`lib/types.ts:437-441`).
public struct SavedLayout: Codable, Sendable, Equatable, Hashable {
  public var width: Double
  public var height: Double
  public var layout: [LayoutItem]

  public init(width: Double, height: Double, layout: [LayoutItem]) {
    self.width = width
    self.height = height
    self.layout = layout
  }
}

/// `focus` or `rest` (`lib/types.ts:381`).
public struct PomodoroPhase: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let focus = PomodoroPhase(rawValue: "focus")
  public static let rest = PomodoroPhase(rawValue: "rest")
  public static let known: [PomodoroPhase] = [.focus, .rest]
}

/// The server-side timer (`lib/types.ts:383-391`), also the answer of
/// `POST /api/pomodoro/start|pause|reset`.
public struct PomodoroState: Codable, Sendable, Equatable, Hashable {
  public var enabled: Bool
  public var phase: PomodoroPhase
  public var running: Bool
  public var remainingSeconds: Int
  public var focusMinutes: Int
  public var restMinutes: Int
  public var completedFocusCount: Int

  public init(
    enabled: Bool,
    phase: PomodoroPhase,
    running: Bool,
    remainingSeconds: Int,
    focusMinutes: Int,
    restMinutes: Int,
    completedFocusCount: Int
  ) {
    self.enabled = enabled
    self.phase = phase
    self.running = running
    self.remainingSeconds = remainingSeconds
    self.focusMinutes = focusMinutes
    self.restMinutes = restMinutes
    self.completedFocusCount = completedFocusCount
  }

  /// A stopped, disabled timer with the server's default lengths
  /// (`lib/pomodoro.ts:3-4`), for previews and a state built in code.
  public static let disabled = PomodoroState(
    enabled: false,
    phase: .focus,
    running: false,
    remainingSeconds: 25 * 60,
    focusMinutes: 25,
    restMinutes: 5,
    completedFocusCount: 0
  )
}

/// Where a notification came from (`lib/types.ts:367`).
public struct NotificationSource: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let jiraMention = NotificationSource(rawValue: "jira_mention")
  public static let pullRequest = NotificationSource(rawValue: "pull_request")
  public static let email = NotificationSource(rawValue: "email")
  public static let slack = NotificationSource(rawValue: "slack")
  public static let known: [NotificationSource] = [.jiraMention, .pullRequest, .email, .slack]
}

/// One bell entry (`lib/types.ts:369-379`). `id` is `source:externalId`.
public struct NotificationItem: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var source: NotificationSource
  public var title: String
  public var url: String
  public var read: Bool
  public var date: String

  public init(id: String, source: NotificationSource, title: String, url: String, read: Bool, date: String) {
    self.id = id
    self.source = source
    self.title = title
    self.url = url
    self.read = read
    self.date = date
  }
}

/// `POST /api/notifications/read` (`app/api/notifications/read/route.ts:52`,
/// `lib/notifications.ts:40-43`): how many were newly marked.
public struct NotificationsReadResult: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var marked: Int

  public init(ok: Bool, marked: Int) {
    self.ok = ok
    self.marked = marked
  }
}

/// A Slack mention or direct message (`lib/types.ts:352-359`).
public struct SlackMessage: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var channel: String
  public var author: String
  public var text: String
  public var date: String
  public var url: String

  public init(id: String, channel: String, author: String, text: String, date: String, url: String) {
    self.id = id
    self.channel = channel
    self.author = author
    self.text = text
    self.date = date
    self.url = url
  }
}

/// The Slack panel (`lib/types.ts:361-365`).
public struct SlackDigest: Codable, Sendable, Equatable, Hashable {
  public var mentions: [SlackMessage]
  public var directs: [SlackMessage]
  public var team: String

  public init(mentions: [SlackMessage], directs: [SlackMessage], team: String) {
    self.mentions = mentions
    self.directs = directs
    self.team = team
  }
}
