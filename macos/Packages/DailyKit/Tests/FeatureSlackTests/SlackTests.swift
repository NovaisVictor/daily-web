import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureSlack

private func message(_ id: String, date: String = "2026-11-04T12:00:00.000Z", url: String = "https://x.slack.com/a")
  -> SlackMessage
{
  SlackMessage(id: id, channel: "#geral", author: "Carla", text: "oi", date: date, url: url)
}

private let digest = SlackDigest(
  mentions: [message("m1"), message("m2")], directs: [message("d1", url: "")], team: "Exemplo")

@Suite struct SlackTabTests {
  @Test func itemsPerTab() {
    #expect(SlackTab.mentions.items(in: digest).map(\.id) == ["m1", "m2"])
    #expect(SlackTab.directs.items(in: digest).map(\.id) == ["d1"])
    #expect(SlackTab.mentions.items(in: nil).isEmpty)
  }

  @Test func emptyTextsAreTheWebs() {
    #expect(SlackTab.mentions.emptyText == "Nenhuma menção nos últimos 7 dias.")
    #expect(SlackTab.directs.emptyText == "Nenhuma mensagem direta não lida.")
  }

  @Test func findsTheTabOfAMessage() {
    #expect(SlackTab.containing("d1", in: digest) == .directs)
    #expect(SlackTab.containing("m2", in: digest) == .mentions)
    #expect(SlackTab.containing("gone", in: digest) == nil)
  }
}

@Suite struct SlackDatesTests {
  let now = Date(timeIntervalSince1970: 1_793_000_000)

  func iso(_ offset: TimeInterval) -> String {
    JSISODate.string(from: now.addingTimeInterval(offset))
  }

  @Test func followsTheWebSteps() throws {
    #expect(try #require(SlackDates.relativeParts(iso(-30), now: now)) == (.second, -30))
    #expect(try #require(SlackDates.relativeParts(iso(-5 * 60), now: now)) == (.minute, -5))
    #expect(try #require(SlackDates.relativeParts(iso(-3 * 3600), now: now)) == (.hour, -3))
    #expect(try #require(SlackDates.relativeParts(iso(-86_400), now: now)) == (.day, -1))
    #expect(try #require(SlackDates.relativeParts(iso(-14 * 86_400), now: now)) == (.weekOfMonth, -2))
    #expect(try #require(SlackDates.relativeParts(iso(-400 * 86_400), now: now)) == (.year, -1))
  }

  /// `Math.round(-2.5)` is -2 in JavaScript.
  @Test func roundsHalvesUpLikeJavaScript() throws {
    #expect(try #require(SlackDates.relativeParts(iso(-150), now: now)) == (.minute, -2))
  }

  @Test func readsDatesWithoutMilliseconds() {
    #expect(SlackDates.parse("2026-11-04T12:00:00Z") != nil)
    #expect(SlackDates.parse("2026-11-04T12:00:00.123Z") != nil)
  }

  @Test func unreadableDateIsADash() {
    #expect(SlackDates.relative("", now: now) == "—")
    #expect(SlackDates.relative("ontem", now: now) == "—")
  }

  @Test func namesYesterdayInPortuguese() {
    #expect(SlackDates.relative(iso(-86_400), now: now) == "ontem")
  }
}

@MainActor
@Suite struct SlackStoreTests {
  let navigator = AppNavigator()
  let dashboard = DashboardStore(client: PreviewAPIClient(responses: [:]), cache: nil, toasts: ToastCenter())
  let store: SlackStore

  init() {
    store = SlackStore(dashboard: dashboard, navigator: navigator)
  }

  func load(_ slack: PanelResult<SlackDigest>) {
    dashboard.apply(DashboardState(updatedAt: "x", modules: [.slack], slack: slack))
  }

  @Test func loadingUntilTheFirstState() {
    #expect(store.isLoading)
    #expect(!store.showsEmpty)
  }

  @Test func listsTheChosenTab() {
    load(PanelResult(data: digest, error: nil))
    #expect(store.team == "Exemplo")
    #expect(store.items.map(\.id) == ["m1", "m2"])
    #expect(store.count(.directs) == 1)
    store.tab = .directs
    #expect(store.items.map(\.id) == ["d1"])
  }

  @Test func emptyOnlyWithoutError() {
    load(PanelResult(data: SlackDigest(mentions: [], directs: [], team: ""), error: nil))
    #expect(store.showsEmpty)
    load(PanelResult(data: nil, error: "Slack fora do ar"))
    #expect(store.error == "Slack fora do ar")
    #expect(!store.showsEmpty)
  }

  @Test func revealsTheMessageANotificationPointsAt() {
    load(PanelResult(data: digest, error: nil))
    navigator.open(.module(.slack), itemID: "d1")
    store.revealPending()
    #expect(store.tab == .directs)
    #expect(store.selection == "d1")
    #expect(store.scrollTarget == "d1")
    #expect(navigator.pending == nil)
  }

  @Test func keepsTheRequestUntilTheDigestArrives() {
    navigator.open(.module(.slack), itemID: "d1")
    store.revealPending()
    #expect(store.pendingItemID == "d1")
    load(PanelResult(data: nil, error: "Slack fora do ar"))
    store.revealPending()
    #expect(store.pendingItemID == "d1")

    load(PanelResult(data: digest, error: nil))
    store.revealPending()
    #expect(store.selection == "d1")
    #expect(navigator.pending == nil)
  }

  @Test func finishesAMessageThatLeftTheDigest() {
    load(PanelResult(data: digest, error: nil))
    navigator.open(.module(.slack), itemID: "gone")
    store.revealPending()
    #expect(store.tab == .mentions)
    #expect(store.selection == nil)
    #expect(navigator.pending == nil)
  }

  @Test func leavesAnotherScreensRequestAlone() {
    load(PanelResult(data: digest, error: nil))
    navigator.open(.module(.notes), itemID: "d1")
    store.revealPending()
    #expect(store.selection == nil)
    #expect(navigator.pending?.itemID == "d1")
  }

  @Test func linksOnlyWebAddresses() {
    #expect(SlackStore.link(message("a")) != nil)
    #expect(SlackStore.link(message("b", url: "")) == nil)
    #expect(SlackStore.link(message("c", url: "javascript:alert(1)")) == nil)
  }
}
