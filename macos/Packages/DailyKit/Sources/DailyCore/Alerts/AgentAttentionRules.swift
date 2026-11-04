import DailyAPI
import DailyModels
import Foundation
import os

/// Why an agent task needs the user (`NeedsYou`, `components/agents/contracts.ts:19`).
public nonisolated struct AgentNeedsYou: Equatable, Sendable {
  /// `permission`, `input`, `menu`, `decision`, `access` or `credential`.
  public var kind: String
  public var since: String

  public init(kind: String, since: String) {
    self.kind = kind
    self.since = since
  }
}

/// The board rules that decide which agent tasks wait on the user. They live in
/// core because two places read them: the agents screen (every 2 s while shown)
/// and the background check below, and both must report the same keys to the
/// alert engine, which forgets keys it is not given again.
public nonisolated enum AgentAttentionRules {
  static let activeStatuses: [AgentTaskStatus] = [.queued, .working, .waiting, .blocked]

  /// `activityWindows[0]` (`lib/agents/model.ts:35`): the board's default window.
  public static let defaultActivityWindow = 3

  /// `needsYou` (`contracts.ts:34-45`). The hooks raise "input" whenever a turn
  /// ends; the terminal's live state and the agent's own "waiting" status are
  /// stronger evidence than that signal.
  public static func needsYou(_ task: AgentTask) -> AgentNeedsYou? {
    guard activeStatuses.contains(task.status) else { return nil }
    let live = task.assignment?.live
    if live?.state == .working { return nil }
    if task.status == .blocked, let hold = task.hold, [.decision, .access, .credential].contains(hold.reason) {
      return AgentNeedsYou(kind: hold.reason.rawValue, since: task.lastActivityAt)
    }
    let attention = task.assignment?.attention
    if let live, live.state == .prompt {
      return AgentNeedsYou(
        kind: attention?.kind == .permission ? "permission" : "menu",
        since: attention?.since ?? live.since ?? task.lastActivityAt)
    }
    guard let attention else { return nil }
    if let live, [.working, .background, .stopped].contains(live.state) { return nil }
    if attention.kind == .input && task.status == .waiting { return nil }
    return AgentNeedsYou(kind: attention.kind.rawValue, since: attention.since)
  }

  /// The cards the board shows: root tasks active within the window
  /// (`AgentBoard.tsx:34`), even if the server sent more.
  public static func boardTasks(_ tasks: [AgentTask], days: Int, now: Date) -> [AgentTask] {
    let start = now.addingTimeInterval(-Double(days) * 86_400)
    return tasks.filter { task in
      guard task.parentTaskId == nil, let at = date(task.lastActivityAt) else { return false }
      return at > start
    }
  }

  /// What the alert engine gets from an unfiltered board in the default window.
  public static func waiting(_ board: AgentsBoard, now: Date) -> [AgentAttention] {
    boardTasks(board.tasks.items, days: defaultActivityWindow, now: now).compactMap { task in
      needsYou(task).map {
        AgentAttention(
          taskID: task.id, title: task.title, since: $0.since, kind: $0.kind,
          agent: task.assignment?.displayName ?? "")
      }
    }
  }

  /// The server's timestamps, with or without fractional seconds.
  public static func date(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
  }

  /// `GET /api/agents` with the board's default filters (`AgentBoard.tsx:20-26`),
  /// the same query the agents screen sends before any filter changes.
  public static var defaultBoard: Endpoint<AgentsBoard> {
    Endpoint(
      .get, "/api/agents",
      query: [
        URLQueryItem(name: "days", value: String(defaultActivityWindow)),
        URLQueryItem(name: "scope", value: "roots"),
        URLQueryItem(name: "sort", value: "newest"),
        URLQueryItem(name: "limit", value: "100"),
      ])
  }
}

/// FR-006 without the agents screen: once a minute, while that screen is not
/// polling the board itself, reads the default board only to find the tasks
/// waiting on the user. The web has no such check: it relies on web push
/// (`lib/push/dispatch.ts`), which the app does not receive.
@MainActor
final class AgentAttentionCheck {
  private let client: any APIClient
  /// Weak: the poller owns the scope that owns this check.
  private weak var poller: Poller?
  private let alerts: AlertEngine
  private let now: Now

  init(client: any APIClient, poller: Poller, alerts: AlertEngine, now: @escaping Now) {
    self.client = client
    self.poller = poller
    self.alerts = alerts
    self.now = now
  }

  private var screenIsPolling: Bool {
    poller?.registeredScopes.contains(Poller.ScopeID.agents) ?? false
  }

  func run() async {
    // The screen's own 2 s scope reports the same tasks; a second read would
    // only cost a request.
    guard !screenIsPolling else { return }
    do {
      let board = try await client.send(AgentAttentionRules.defaultBoard)
      // The screen may have opened while the request was out; its answer is newer.
      guard !screenIsPolling else { return }
      await alerts.updateAgents(AgentAttentionRules.waiting(board, now: now()))
    } catch {
      if case .cancelled = error { return }
      // The next minute tries again; nothing to show, the person did not ask.
      Logger.core.error("Agent attention check failed: \(String(describing: error), privacy: .public)")
    }
  }
}
