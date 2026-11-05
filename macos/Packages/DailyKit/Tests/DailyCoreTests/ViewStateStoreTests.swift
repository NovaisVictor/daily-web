import Foundation
import Testing

@testable import DailyCore

/// Spec 015 FR-015-01: each panel remembers its view per account and server.
@Suite struct ViewStateStoreTests {
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
