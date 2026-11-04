import DailyAPI
import DailyModels
import Foundation
import Synchronization
import os

/// An `APIClient` for previews: answers from canned JSON, never the network.
public nonisolated final class PreviewAPIClient: APIClient {
  private let responses: [String: Data]

  /// - Parameter responses: Bodies keyed by `"METHOD /path"`, e.g. `"GET /api/state"`.
  public init(responses: [String: Data]) {
    self.responses = responses
  }

  /// Answers `GET /api/me`, `GET /api/state`, `POST /api/refresh` and the
  /// pomodoro actions from the given values; anything else gets `{"ok":true}`.
  public convenience init(state: DashboardState, user: CurrentUser) {
    var responses: [String: Data] = [:]
    let encoder = JSONEncoder()
    do {
      responses["GET /api/me"] = try encoder.encode(user)
      let stateData = try encoder.encode(state)
      responses["GET /api/state"] = stateData
      responses["POST /api/refresh"] = stateData
      for action in ["start", "pause", "reset"] {
        responses["POST /api/pomodoro/\(action)"] = try encoder.encode(state.pomodoro)
      }
    } catch {
      Logger.core.fault("Preview fixtures failed to encode: \(String(describing: error), privacy: .public)")
    }
    self.init(responses: responses)
  }

  public func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
    let data = responses["\(endpoint.method.rawValue) \(endpoint.path)"] ?? Data(#"{"ok":true}"#.utf8)
    if let empty = EmptyResponse() as? Response { return empty }
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw .decoding(detail: String(describing: error))
    }
  }

  public func signIn(server: URL, username: String, password: String) async throws(APIError) {}

  public func signOut() async {}
}

/// Session token and server kept in memory, for previews.
public nonisolated final class InMemorySessionStorage: SessionTokenStore, ServerSettings {
  private let state: Mutex<(server: URL?, tokens: [URL: String])>

  public init(server: URL? = nil, token: String? = nil) {
    var tokens: [URL: String] = [:]
    if let server, let token { tokens[server] = token }
    state = Mutex((server, tokens))
  }

  public func token(for server: URL) throws -> String? { state.withLock { $0.tokens[server] } }
  public func save(_ token: String, for server: URL) throws { state.withLock { $0.tokens[server] = token } }
  public func deleteToken(for server: URL) throws { state.withLock { $0.tokens[server] = nil } }
  public var serverURL: URL? { state.withLock { $0.server } }
  public func setServerURL(_ url: URL?) { state.withLock { $0.server = url } }
}

/// Posts nothing; previews and tests that do not check alerts.
public final class SilentNotificationPoster: NotificationPosting {
  public init() {}
  public func requestAuthorization() async -> Bool { false }
  public func isAuthorized() async -> Bool { false }
  public func post(_ alert: DesktopAlert) async {}
}

/// Sample data for previews. Names and addresses are made up.
public enum PreviewFixtures {
  public static let user = CurrentUser(
    username: "ana", isAdmin: true, avatarUrl: nil, fullName: "Ana Souza", email: "ana@example.com")

  public static var dashboard: DashboardState {
    DashboardState(
      updatedAt: "2026-11-04T12:40:00.000Z",
      modules: [.email, .tasks, .agenda, .slack],
      mailboxes: [MailboxRef(id: "conn-mail-1", label: "Trabalho")],
      agendaDays: 2,
      agendaCalendars: [
        AgendaCalendarRef(id: "primary", label: "Agenda pessoal", account: "conn-cal-1", canWrite: true)
      ],
      email: PanelResult(
        data: [
          EmailEnvelope(
            id: "4182", account: "conn-mail-1", accountLabel: "Trabalho", from: "Ana Exemplo <ana@example.com>",
            subject: "Revisão do relatório trimestral", unread: true, date: "2026-11-04T12:31:00.000Z",
            messageId: "<msg-4182@example.com>", references: [], labels: [], mailbox: .inbox, folder: "INBOX"),
          EmailEnvelope(
            id: "4183", account: "conn-mail-1", accountLabel: "Trabalho", from: "Bruno Teste <bruno@example.com>",
            subject: "Re: agenda da semana", unread: false, date: "2026-11-04T11:02:00.000Z",
            messageId: "<msg-4183@example.com>", references: [], labels: [], mailbox: .inbox, folder: "INBOX"),
        ],
        error: nil),
      agenda: PanelResult(
        data: [
          AgendaItem(
            account: "conn-cal-1", accountLabel: "Agenda pessoal", date: "2026-11-04", time: "14:30",
            title: "Reunião de planejamento"),
          AgendaItem(
            account: "conn-cal-1", accountLabel: "Agenda pessoal", date: "2026-11-05", time: "",
            title: "Feriado municipal"),
        ],
        error: nil),
      tasks: PanelResult(data: [], error: nil),
      slack: PanelResult(
        data: SlackDigest(
          mentions: [
            SlackMessage(
              id: "C1-1730720000.000100", channel: "#produto", author: "Carla", text: "@ana pode revisar?",
              date: "2026-11-04T12:10:00.000Z", url: "https://example.slack.com/archives/C1/p1730720000000100")
          ],
          directs: [],
          team: "Exemplo"),
        error: nil),
      notifications: PanelResult(
        data: [
          NotificationItem(
            id: "slack:C1-1730720000.000100", source: .slack, title: "Carla mencionou você",
            url: "https://example.slack.com/archives/C1/p1730720000000100", read: false,
            date: "2026-11-04T12:10:00.000Z")
        ],
        error: nil),
      pomodoro: PomodoroState(
        enabled: true, phase: .focus, running: false, remainingSeconds: 25 * 60, focusMinutes: 25, restMinutes: 5,
        completedFocusCount: 2)
    )
  }
}
