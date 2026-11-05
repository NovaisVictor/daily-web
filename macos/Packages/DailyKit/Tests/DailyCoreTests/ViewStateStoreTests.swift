import Foundation
import Testing

@testable import DailyCore

/// Spec 015 FR-015-01: each panel remembers its view per account and server.
@Suite struct ViewStateStoreTests {
  final class Owner {}
  nonisolated enum Tab: String {
    case first, second
  }

  let defaults = Fixtures.defaults()

  nonisolated static let server = URL(string: "https://daily.example.com") ?? URL(filePath: "/")
  nonisolated static let otherServer = URL(string: "https://outro.example.com:8443") ?? URL(filePath: "/")

  func signedIn(_ username: String = "ana", server: URL = Self.server) -> ViewStateStore {
    let store = ViewStateStore(defaults: defaults)
    store.activate(server: server, username: username)
    return store
  }

  @Test func valuesSurviveARelaunch() {
    let store = signedIn()
    store.set("problemas", module: "jira", field: "tab")
    store.set(true, module: "email", field: "maximized")

    // A new launch reads the last account before the session is checked.
    let relaunched = ViewStateStore(defaults: defaults)
    #expect(relaunched.isActive)
    #expect(relaunched.string(module: "jira", field: "tab") == "problemas")
    #expect(relaunched.bool(module: "email", field: "maximized") == true)
  }

  @Test func eachAccountAndServerKeepsItsOwn() {
    signedIn("ana").set("revisoes", module: "pulls", field: "tab")
    #expect(signedIn("bia").string(module: "pulls", field: "tab") == nil)
    #expect(signedIn("ana", server: Self.otherServer).string(module: "pulls", field: "tab") == nil)
    #expect(signedIn("ana").string(module: "pulls", field: "tab") == "revisoes")
  }

  @Test func signOutKeepsTheValuesForTheNextSignIn() {
    let store = signedIn()
    store.set("directs", module: "slack", field: "tab")
    store.deactivate()
    #expect(!store.isActive)
    #expect(store.string(module: "slack", field: "tab") == nil)
    // Signed out, nothing is written anywhere.
    store.set("mentions", module: "slack", field: "tab")
    #expect(!ViewStateStore(defaults: defaults).isActive)

    store.activate(server: Self.server, username: "ana")
    #expect(store.string(module: "slack", field: "tab") == "directs")
  }

  @Test func emptyOrNilForgetsAndFalseIsAValue() {
    let store = signedIn()
    #expect(store.bool(module: "email", field: "onlyUnread") == nil)
    store.set(false, module: "email", field: "onlyUnread")
    #expect(store.bool(module: "email", field: "onlyUnread") == false)

    store.set("x", module: "email", field: "query")
    store.set("", module: "email", field: "query")
    #expect(store.string(module: "email", field: "query") == nil)
    store.set("y", module: "email", field: "query")
    store.set(nil, module: "email", field: "query")
    #expect(store.string(module: "email", field: "query") == nil)
  }

  /// The keys are on disk: moving the derivation into `AccountScope` must not
  /// change them, or every account would forget its view and appearance.
  @Test func keysKeepTheirFormat() {
    let store = signedIn()
    store.set("problemas", module: "jira", field: "tab")
    let account = "io.github.novaisvictor.dailyweb.viewState.https://daily.example.com|ana"
    #expect(defaults.string(forKey: "io.github.novaisvictor.dailyweb.viewStateAccount") == account)
    #expect(defaults.string(forKey: "\(account).jira.tab") == "problemas")
    #expect(
      AccountScope.key(prefix: PreferencesStore.appearanceKey, server: Self.otherServer, username: "bia")
        == "io.github.novaisvictor.dailyweb.appearance.https://outro.example.com:8443|bia")
    #expect(AccountScope.key(prefix: "x", server: URL(filePath: "/tmp/daily"), username: "ana") == nil)
  }

  @Test func enumsAreKeptByTheirRawValue() {
    let store = signedIn()
    #expect(store.value(Tab.self, module: "jira", field: "tab") == nil)
    store.set(Tab.second, module: "jira", field: "tab")
    #expect(store.string(module: "jira", field: "tab") == "second")
    #expect(store.value(Tab.self, module: "jira", field: "tab") == .second)
    // A value no longer among the cases reads as nothing, not as a failure.
    store.set("gone", module: "jira", field: "tab")
    #expect(store.value(Tab.self, module: "jira", field: "tab") == nil)
    store.set(Tab?.none, module: "jira", field: "tab")
    #expect(store.string(module: "jira", field: "tab") == nil)
  }

  /// A store built while the session is checked read no account, or the last
  /// one; the sign-in tells it to read the signed-in account's values.
  @Test func signingInAsAnotherAccountTellsTheObservers() {
    signedIn("ana").set("problemas", module: "jira", field: "tab")
    let store = ViewStateStore(defaults: defaults)
    store.deactivate()
    let owner = Owner()
    var restored: [String?] = []
    store.observe(owner) { restored.append(store.string(module: "jira", field: "tab")) }

    store.activate(server: Self.server, username: "ana")
    #expect(restored == ["problemas"])
    // The same account again: what was read still holds.
    store.activate(server: Self.server, username: "ana")
    #expect(restored == ["problemas"])
    store.activate(server: Self.server, username: "bia")
    #expect(restored == ["problemas", nil])
    withExtendedLifetime(owner) {}
  }

  @Test func aReleasedObserverIsNotCalled() {
    let store = ViewStateStore(defaults: defaults)
    store.deactivate()
    var owner: Owner? = Owner()
    var calls = 0
    if let owner { store.observe(owner) { calls += 1 } }
    owner = nil
    store.activate(server: Self.server, username: "ana")
    #expect(calls == 0)
    #expect(owner == nil)
  }

  @Test func rememberedValueReadsNowAndAfterEachAccountSwitch() {
    signedIn("ana").set(Tab.second, module: "jira", field: "tab")
    let store = ViewStateStore(defaults: defaults)
    store.deactivate()
    let owner = Owner()
    let tab = RememberedValue<Tab>(store, module: "jira", field: "tab")
    var applied: [Tab?] = []
    tab.bind(owner) { applied.append($0) }
    #expect(applied == [nil])

    store.activate(server: Self.server, username: "ana")
    #expect(applied == [nil, .second])
    tab.save(.first)
    #expect(tab.stored == .first)
    #expect(RememberedValue<Tab>(nil, module: "jira", field: "tab").stored == nil)
    withExtendedLifetime(owner) {}
  }

  @Test func aServerWithoutAnOriginRemembersNothing() {
    let store = signedIn()
    store.activate(server: URL(filePath: "/tmp/daily"), username: "ana")
    #expect(!store.isActive)
  }
}

@Suite struct NotesEventsTests {
  final class Owner {}

  @Test func postReachesEveryLiveObserver() {
    let events = NotesEvents()
    let first = Owner()
    let second = Owner()
    var heard: [String] = []
    events.observe(first) { heard.append("1:\($0.activate ?? "-")") }
    events.observe(second) { heard.append("2:\($0.activate ?? "-")") }
    events.post(NotesEvents.Change(activate: "n1"))
    events.post(NotesEvents.Change(activate: nil))
    #expect(heard == ["1:n1", "2:n1", "1:-", "2:-"])
    #expect(events.observerCount == 2)
    withExtendedLifetime((first, second)) {}
  }

  @Test func aReleasedOwnerIsNoLongerCalled() {
    let events = NotesEvents()
    var owner: Owner? = Owner()
    var calls = 0
    if let owner { events.observe(owner) { _ in calls += 1 } }
    owner = nil
    events.post(NotesEvents.Change(activate: "n1"))
    #expect(calls == 0)
    #expect(events.observerCount == 0)
    #expect(owner == nil)
  }
}
