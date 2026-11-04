import DailyAPI
import DailyModels
import Foundation

/// `PATCH /api/preferences` (`app/api/preferences/route.ts`). The server reads
/// only the first key present, so every body carries exactly one.
public nonisolated enum PreferencesEndpoints {
  struct AppearanceBody: Encodable, Sendable {
    let appearance: Appearance
  }

  struct AgendaDaysBody: Encodable, Sendable {
    let agendaDays: Int
  }

  struct TasksViewBody: Encodable, Sendable {
    let tasksView: TasksView
  }

  /// Partial: absent fields keep their saved value (`lib/preferences.ts:225-240`).
  public static func appearance(_ patch: Appearance) -> Endpoint<AppearanceResponse> {
    Endpoint(.patch, "/api/preferences", body: AppearanceBody(appearance: patch))
  }

  /// Answers the whole state, refetched for the new window (`route.ts:100-107`).
  public static func agendaDays(_ days: Int) -> Endpoint<DashboardState> {
    Endpoint(.patch, "/api/preferences", body: AgendaDaysBody(agendaDays: days))
  }

  public static func tasksView(_ view: TasksView) -> Endpoint<TasksViewResponse> {
    Endpoint(.patch, "/api/preferences", body: TasksViewBody(tasksView: view))
  }
}

/// `POST /api/pomodoro/start|pause|reset`; the timer lives in the server's memory.
public nonisolated enum PomodoroEndpoints {
  public static var start: Endpoint<PomodoroState> { Endpoint(.post, "/api/pomodoro/start") }
  public static var pause: Endpoint<PomodoroState> { Endpoint(.post, "/api/pomodoro/pause") }
  public static var reset: Endpoint<PomodoroState> { Endpoint(.post, "/api/pomodoro/reset") }
}

/// What a focus block is about (`FocusSource`, `lib/focusBlock.ts:3-8`).
public nonisolated struct FocusSource: Codable, Sendable, Equatable, Hashable {
  public enum Kind: String, Codable, Sendable, Equatable, Hashable {
    case task
    case jira
    case pull
  }

  public var kind: Kind
  public var ref: String
  public var title: String
  public var url: String?

  public init(kind: Kind, ref: String, title: String, url: String? = nil) {
    self.kind = kind
    self.ref = ref
    self.title = title
    self.url = url
  }
}

/// Body of `POST /api/agenda/focus-blocks` (`components/FocusBlockProvider.tsx:85`).
public nonisolated struct FocusBlockRequest: Encodable, Sendable, Equatable {
  public var connectionId: String
  public var item: FocusSource
  /// ISO 8601 in UTC with milliseconds, as `Date.toISOString()` writes it.
  public var start: String
  public var minutes: Int
}

public nonisolated enum AgendaEndpoints {
  public static func focusBlock(_ request: FocusBlockRequest) -> Endpoint<FocusBlockResponse> {
    Endpoint(.post, "/api/agenda/focus-blocks", body: request)
  }
}
