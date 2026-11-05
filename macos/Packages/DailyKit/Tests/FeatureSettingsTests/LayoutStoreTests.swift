import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import FeatureSettings

@Suite struct LayoutStoreTests {
  let client = RecordingAPIClient()
  let reloads = ChangeCounter()
  let store: LayoutStore

  nonisolated static let defaultLayout = [
    LayoutItem(i: "email", x: 0, y: 0, w: 6, h: 12), LayoutItem(i: "tasks", x: 6, y: 0, w: 6, h: 12),
  ]

  init() {
    let reloads = self.reloads
    store = LayoutStore(client: client) { reloads.count += 1 }
    client.respond { call in
      switch (call.method, call.path) {
      case ("GET", "/api/preferences/layout-default"):
        return RecordingAPIClient.json(LayoutDefaultResponse(layout: Self.defaultLayout))
      default:
        return RecordingAPIClient.json(LayoutResponse(layout: Self.defaultLayout, layouts: []))
      }
    }
  }

  @Test func isUnknownUntilTheDefaultAndTheStateArrive() async {
    #expect(store.status(current: Self.defaultLayout) == .unknown)
    await store.load()
    #expect(client.calls.map { "\($0.method) \($0.path)" } == ["GET /api/preferences/layout-default"])
    #expect(store.status(current: nil) == .unknown)
  }

  @Test func theSameLayoutIsTheDefault() async {
    await store.load()
    #expect(store.status(current: Self.defaultLayout) == .isDefault)
  }

  @Test func aMovedPanelOrAnotherOrderIsCustomized() async {
    await store.load()
    var moved = Self.defaultLayout
    moved[1].h = 20
    #expect(store.status(current: moved) == .customized)
    // The web compares the JSON strings, so the order counts too.
    #expect(store.status(current: Self.defaultLayout.reversed()) == .customized)
  }

  @Test func aFailedLoadShowsTheErrorAndStaysUnknown() async {
    client.respond { _ throws(APIError) in throw .offline }
    await store.load()
    #expect(store.error != nil)
    #expect(store.status(current: Self.defaultLayout) == .unknown)
  }

  @Test func restoreSendsANullLayoutAndReloadsTheDashboard() async throws {
    await store.restore()
    let call = try #require(client.calls.last)
    #expect(call.method == "PATCH")
    #expect(call.path == "/api/preferences")
    #expect(call.body == #"{"layout":null}"#)
    #expect(reloads.count == 1)
    #expect(store.isRestoring == false)
    #expect(store.error == nil)
  }

  @Test func aFailedRestoreShowsTheWebTextAndDoesNotReload() async {
    client.respond { _ throws(APIError) in throw .offline }
    await store.restore()
    #expect(store.error == "Falha ao restaurar a disposição")
    #expect(reloads.count == 0)
    #expect(store.isRestoring == false)
  }
}
