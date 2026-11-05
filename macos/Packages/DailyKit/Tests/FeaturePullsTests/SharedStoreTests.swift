import DailyCore
import Testing

@testable import FeaturePulls

@MainActor
@Suite struct SharedStoreTests {
  @Test func theScreenAndThePanelGetTheSameStore() {
    let environment = AppEnvironment.preview()
    let store = PullsStore.shared(in: environment)
    store.tab = .mine
    store.reposExpanded = true
    let again = PullsStore.shared(in: environment)
    #expect(again === store)
    #expect(again.tab == .mine)
    #expect(again.reposExpanded)
  }

  @Test func signingOutStartsOver() {
    let environment = AppEnvironment.preview()
    let store = PullsStore.shared(in: environment)
    environment.featureStores.removeAll()
    #expect(PullsStore.shared(in: environment) !== store)
  }
}
