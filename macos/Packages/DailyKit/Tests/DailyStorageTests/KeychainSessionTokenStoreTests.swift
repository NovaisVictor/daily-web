import Foundation
import Security
import Testing

@testable import DailyStorage

/// Each test uses its own service, so parallel runs never see each other's items,
/// and removes every item it created.
private struct KeychainFixture: ~Copyable {
  let store: KeychainSessionTokenStore
  let server: URL

  init(useDataProtectionKeychain: Bool) throws {
    store = KeychainSessionTokenStore(
      service: "io.github.novaisvictor.dailyweb.tests.\(UUID().uuidString)",
      useDataProtectionKeychain: useDataProtectionKeychain
    )
    server = try #require(URL(string: "http://localhost:3000"))
  }

  deinit {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: store.service,
      kSecUseDataProtectionKeychain as String: store.useDataProtectionKeychain,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      Issue.record("Keychain cleanup failed with OSStatus \(status)")
    }
  }
}

/// Command-line test runs are unsigned, so the data protection keychain answers
/// `errSecMissingEntitlement`; those tests run only where it is reachable.
private let dataProtectionKeychainAvailable: Bool = {
  // A read of a missing item succeeds without the entitlement, so the probe writes.
  let probe: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "io.github.novaisvictor.dailyweb.tests.probe.\(UUID().uuidString)",
    kSecUseDataProtectionKeychain as String: true,
  ]
  var item = probe
  item[kSecValueData as String] = Data("probe".utf8)
  let status = SecItemAdd(item as CFDictionary, nil)
  if status == errSecSuccess {
    SecItemDelete(probe as CFDictionary)
  }
  return status != errSecMissingEntitlement
}()

@Test func loginKeychainRoundTrip() throws {
  let fixture = try KeychainFixture(useDataProtectionKeychain: false)
  try roundTrip(fixture)
}

@Test(.enabled(if: dataProtectionKeychainAvailable, "Unsigned test host has no data protection keychain entitlement"))
func dataProtectionKeychainRoundTrip() throws {
  let fixture = try KeychainFixture(useDataProtectionKeychain: true)
  try roundTrip(fixture)
}

private func roundTrip(_ fixture: borrowing KeychainFixture) throws {
  let store = fixture.store
  #expect(try store.token(for: fixture.server) == nil)

  try store.save("first", for: fixture.server)
  #expect(try store.token(for: fixture.server) == "first")

  // Update path: a second save replaces the item instead of failing as a duplicate.
  try store.save("second", for: fixture.server)
  #expect(try store.token(for: fixture.server) == "second")

  // The account is the origin, so any URL on the same server finds the token.
  let samePage = try #require(URL(string: "http://LOCALHOST:3000/config"))
  #expect(try store.token(for: samePage) == "second")
  let otherPort = try #require(URL(string: "http://localhost:3001"))
  #expect(try store.token(for: otherPort) == nil)

  try store.deleteToken(for: fixture.server)
  #expect(try store.token(for: fixture.server) == nil)
  // Deleting again is not an error.
  try store.deleteToken(for: fixture.server)
}

@Test func keychainRejectsNonHTTPServer() throws {
  let store = KeychainSessionTokenStore(service: "unused", useDataProtectionKeychain: false)
  let url = try #require(URL(string: "file:///tmp"))
  #expect(throws: KeychainError.invalidServer) { try store.save("x", for: url) }
}
