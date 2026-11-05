import Testing

@testable import DailyCore

@Suite struct FeatureStoresTests {
  final class Probe {}

  @Test func theSameKeyReturnsTheSameStore() {
    let stores = FeatureStores()
    let first = stores.store("email") { Probe() }
    let second = stores.store("email") { Probe() }
    #expect(first === second)
  }

  @Test func removeAllStartsOver() {
    let stores = FeatureStores()
    let first = stores.store("email") { Probe() }
    stores.removeAll()
    #expect(stores.store("email") { Probe() } !== first)
  }
}
