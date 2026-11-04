import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Synchronization
import Testing

@testable import FeatureNotifications

/// The server: what `GET /api/state` answers and how every other call is answered.
nonisolated final class FakeServer: Sendable {
  typealias Route = @Sendable (FakeAPIClient.Call) throws(APIError) -> Data?
  private let state: Mutex<(dashboard: DashboardState, route: Route)>

  init(_ dashboard: DashboardState) {
    state = Mutex((dashboard, { _ in nil }))
  }

  func setState(_ dashboard: DashboardState) { state.withLock { $0.dashboard = dashboard } }
  func route(_ route: @escaping Route) { state.withLock { $0.route = route } }

  func answer(_ call: FakeAPIClient.Call) throws(APIError) -> Data {
    let (dashboard, route) = state.withLock { ($0.dashboard, $0.route) }
    if call.path == "/api/state" { return FakeAPIClient.json(dashboard) }
    return try route(call) ?? FakeAPIClient.json(NotificationsReadResult(ok: true, marked: 1))
  }
}

final class FakePoster: NotificationPosting {
  var grants: Bool
  private(set) var requests = 0

  init(grants: Bool) {
    self.grants = grants
  }

  func requestAuthorization() async -> Bool {
    requests += 1
    return grants
  }

  func isAuthorized() async -> Bool { grants }
  func post(_ alert: DesktopAlert) async {}
}

@MainActor
@Suite struct NotificationsStoreTests {
  let client = FakeAPIClient()
  let server: FakeServer
  let dashboard: DashboardStore
  let poster = FakePoster(grants: true)
  let alerts: AlertEngine
  let navigator = AppNavigator()
  let store: NotificationsStore
  let failure = APIError.server(status: 502, message: "banco fora do ar", code: nil, retry: nil)

  static let items = [
    notice("jira_mention:ABC-1", .jiraMention),
    notice("pull_request:o/r#2", .pullRequest, read: true),
    notice("email:<m@x>", .email, url: ""),
    notice("slack:C1-1", .slack),
  ]

  static func state(_ items: [NotificationItem] = items, modules: [ModuleID] = [.email]) -> DashboardState {
    DashboardState(updatedAt: "x", modules: modules, notifications: PanelResult(data: items, error: nil))
  }

  init() throws {
    let server = FakeServer(Self.state())
    self.server = server
    client.respond { call throws(APIError) in try server.answer(call) }
    let toasts = quietToasts()
    dashboard = DashboardStore(client: client, cache: nil, toasts: toasts)
    let defaults = try #require(UserDefaults(suiteName: "FeatureNotificationsTests-\(UUID().uuidString)"))
    alerts = AlertEngine(poster: poster, cache: nil, defaults: defaults)
    store = NotificationsStore(client: client, dashboard: dashboard, alerts: alerts, navigator: navigator)
    dashboard.apply(Self.state())
  }

  var unreadIDs: [String] { store.unread.map(\.id) }

  // MARK: - Mark one

  @Test func markReadPostsTheIDAndDropsTheBadge() async {
    #expect(store.unreadCount == 3)
    await store.markRead(Self.items[0])
    #expect(client.actionCalls == [.init("POST", "/api/notifications/read", body: #"{"id":"jira_mention:ABC-1"}"#)])
    #expect(unreadIDs == ["email:<m@x>", "slack:C1-1"])
    #expect(store.error == nil)
  }

  @Test func markReadKeepsSlashesAndHashesInTheBody() async {
    await store.markRead(notice("pull_request:o/r#9:stale-review", .pullRequest))
    #expect(client.actionCalls.first?.body == #"{"id":"pull_request:o/r#9:stale-review"}"#)
  }

  @Test func markReadFailureRollsBack() async {
    let failure = failure
    server.route { _ throws(APIError) in throw failure }
    await store.markRead(Self.items[0])
    #expect(store.unreadCount == 3)
    #expect(store.error == "banco fora do ar")
  }

  // MARK: - Shared helper (the app's "Marcar como lida" action)

  @Test func readingHelperSendsOneIDAsTheBellDoes() async {
    let failure = await NotificationsReading.markRead(ids: ["slack:C1-1"], client: client, dashboard: dashboard)
    #expect(failure == nil)
    #expect(client.actionCalls == [.init("POST", "/api/notifications/read", body: #"{"id":"slack:C1-1"}"#)])
    #expect(unreadIDs == ["jira_mention:ABC-1", "email:<m@x>"])
  }

  @Test func readingHelperRollsBackOnFailure() async {
    let failure = failure
    server.route { _ throws(APIError) in throw failure }
    let result = await NotificationsReading.markRead(
      ids: ["slack:C1-1", "email:<m@x>"], client: client, dashboard: dashboard)
    #expect(result == failure)
    #expect(client.actionCalls.first?.body == #"{"ids":["slack:C1-1","email:<m@x>"]}"#)
    #expect(store.unreadCount == 3)
  }

  // MARK: - Mark all

  @Test func markAllSendsTheUnreadIDs() async {
    await store.markAllRead()
    let body = #"{"ids":["jira_mention:ABC-1","email:<m@x>","slack:C1-1"]}"#
    #expect(client.actionCalls == [.init("POST", "/api/notifications/read", body: body)])
    #expect(store.unreadCount == 0)
    #expect(!store.markingAll)
  }

  @Test func markAllDoesNothingWithoutUnread() async {
    dashboard.apply(
      Self.state(
        Self.items.map {
          var item = $0; item.read = true; return item
        }))
    await store.markAllRead()
    #expect(client.actionCalls.isEmpty)
  }

  @Test func markAllChunksAboveTwoHundred() async {
    let many = (0..<450).map { notice("email:<\($0)@x>", .email, url: "") }
    dashboard.apply(Self.state(many))
    await store.markAllRead()
    let bodies = client.actionCalls.map(\.body)
    #expect(client.actionCalls.allSatisfy { $0.method == "POST" && $0.path == "/api/notifications/read" })
    #expect(bodies.count == 3)
    let sent = bodies.compactMap { $0 }.map(Self.ids)
    #expect(sent.map(\.count) == [200, 200, 50])
    #expect(sent.flatMap { $0 } == many.map(\.id))
    #expect(store.unreadCount == 0)
  }

  @Test func markAllFailureRollsBack() async {
    let failure = failure
    server.route { _ throws(APIError) in throw failure }
    await store.markAllRead()
    #expect(store.unreadCount == 3)
    #expect(store.error == "banco fora do ar")
    #expect(!store.markingAll)
  }

  /// The first piece was saved: the rollback is replaced by the server's state.
  @Test func markAllPartialFailureReloadsFromTheServer() async {
    let many = (0..<250).map { notice("email:<\($0)@x>", .email, url: "") }
    dashboard.apply(Self.state(many))
    var saved = many
    for index in 0..<200 { saved[index].read = true }
    server.setState(Self.state(saved))
    let failure = failure
    let count = Mutex(0)
    server.route { call throws(APIError) in
      guard call.path == "/api/notifications/read" else { return nil }
      let index = count.withLock { value in
        value += 1
        return value
      }
      if index == 2 { throw failure }
      return nil
    }
    await store.markAllRead()
    #expect(store.unreadCount == 50)
    #expect(store.error == "banco fora do ar")
    #expect(client.calls.last?.path == "/api/state")
  }

  // MARK: - Filter

  @Test func filterTogglesSources() {
    store.toggle(.slack)
    #expect(store.visibleItems.map(\.id) == ["slack:C1-1"])
    store.toggle(.email)
    #expect(store.visibleItems.map(\.id) == ["email:<m@x>", "slack:C1-1"])
    store.toggle(.slack)
    store.toggle(.email)
    #expect(store.visibleItems.count == 4)
  }

  // MARK: - Reply

  @Test func replyOnlyOnJiraMentions() {
    store.toggleReply(Self.items[3])
    #expect(store.reply == nil)
    store.toggleReply(Self.items[0])
    #expect(store.reply?.issueKey == "ABC-1")
    store.toggleReply(Self.items[0])
    #expect(store.reply == nil)
  }

  @Test func replyPostsTheTrimmedCommentAndMarksRead() async {
    server.route { call in
      call.path.hasSuffix("/comments")
        ? FakeAPIClient.json(JiraCommentResponse(ok: true, comment: .init(id: "10"))) : nil
    }
    store.toggleReply(Self.items[0])
    store.reply?.text = "  pode deixar  \n"
    await store.submitReply()
    #expect(
      client.actionCalls == [
        .init("POST", "/api/jira/issues/ABC-1/comments", body: #"{"body":"pode deixar"}"#),
        .init("POST", "/api/notifications/read", body: #"{"id":"jira_mention:ABC-1"}"#),
      ])
    #expect(store.reply?.stage == .published)
    #expect(!unreadIDs.contains("jira_mention:ABC-1"))
  }

  @Test func replyRefusalShowsTheServerText() async {
    let refusal = APIError.server(status: 403, message: "sem permissão para comentar", code: nil, retry: nil)
    server.route { _ throws(APIError) in throw refusal }
    store.toggleReply(Self.items[0])
    store.reply?.text = "oi"
    await store.submitReply()
    #expect(store.reply?.stage == .writing)
    #expect(store.reply?.problem == "sem permissão para comentar")
    #expect(store.reply?.sending == false)
    #expect(unreadIDs.contains("jira_mention:ABC-1"))
  }

  @Test func replyWithoutCommentIDIsUnexpected() async {
    server.route { _ in FakeAPIClient.json(JiraCommentResponse(ok: true, comment: .init(id: ""))) }
    store.toggleReply(Self.items[0])
    store.reply?.text = "oi"
    await store.submitReply()
    #expect(store.reply?.problem == "resposta inesperada do servidor")
  }

  @Test func replyChecksLength() async {
    store.toggleReply(Self.items[0])
    store.reply?.text = "   "
    #expect(store.reply?.ready == false)
    store.reply?.text = String(repeating: "a", count: 5001)
    #expect(store.reply?.problem == "passou de 5000 caracteres (5001)")
    await store.submitReply()
    #expect(client.actionCalls.isEmpty)
  }

  // MARK: - Desktop alerts

  @Test func enablingAsksForPermission() async {
    await store.toggleAlerts()
    #expect(poster.requests == 1)
    #expect(store.alertsEnabled)
    #expect(!store.alertsDenied)
    await store.toggleAlerts()
    #expect(!store.alertsEnabled)
  }

  @Test func deniedPermissionIsShown() async {
    poster.grants = false
    await store.toggleAlerts()
    #expect(!store.alertsEnabled)
    #expect(store.alertsDenied)
  }

  // MARK: - Opening

  @Test func opensLinksInTheBrowserAndEmailInTheApp() {
    #expect(store.destination(Self.items[0]) == .browser(URL(string: "https://x/1")!))
    #expect(store.destination(Self.items[2]) == .app(.module(.email), itemID: nil))
    dashboard.apply(Self.state(modules: []))
    #expect(store.destination(Self.items[2]) == nil)
  }

  nonisolated static func ids(_ body: String) -> [String] {
    struct Body: Decodable { let ids: [String] }
    do {
      return try JSONDecoder().decode(Body.self, from: Data(body.utf8)).ids
    } catch {
      Issue.record("Body is not {ids}: \(body)")
      return []
    }
  }
}
