import DailyAPI
import DailyModels
import Foundation
import Testing

@testable import DailyCore

@Suite struct SessionStoreTests {
  let server = URL(string: "https://daily.example.com")
  let client = FakeAPIClient()

  func makeStore(token: String? = "token") -> SessionStore {
    let storage = InMemorySessionStorage(server: server, token: token)
    return SessionStore(client: client, tokenStore: storage, settings: storage)
  }

  @Test func restoreWithoutServerSignsOut() async {
    let storage = InMemorySessionStorage()
    let store = SessionStore(client: client, tokenStore: storage, settings: storage)
    await store.restore()
    #expect(store.phase == .signedOut(message: nil))
    #expect(client.calls.isEmpty)
  }

  @Test func restoreWithoutTokenSignsOut() async {
    let store = makeStore(token: nil)
    await store.restore()
    #expect(store.phase == .signedOut(message: nil))
    #expect(client.calls.isEmpty)
  }

  @Test func restoreWithTokenLoadsTheUser() async {
    client.respond { _ in FakeAPIClient.json(Fixtures.user) }
    let store = makeStore()
    var signedIn: CurrentUser?
    store.onSignedIn = { signedIn = $0 }
    await store.restore()
    #expect(store.phase == .signedIn(Fixtures.user))
    #expect(signedIn == Fixtures.user)
    #expect(client.calls == [.init(method: "GET", path: "/api/me", body: nil)])
  }

  @Test func restoreUnauthorizedSignsOutWithTheExpiredMessage() async {
    client.respond { _ throws(APIError) in throw .unauthorized }
    let store = makeStore()
    await store.restore()
    #expect(store.phase == .signedOut(message: "Sua sessão expirou. Entre de novo."))
  }

  @Test func restoreThatEndsSignedOutRunsTheSignOutCleanup() async {
    // The previous account's cache, alerts and appearance must not survive an
    // expired or missing session at launch.
    client.respond { _ throws(APIError) in throw .unauthorized }
    let expired = makeStore()
    var expiredCleanups = 0
    expired.onSignedOut = { expiredCleanups += 1 }
    await expired.restore()
    #expect(expiredCleanups == 1)

    let missing = makeStore(token: nil)
    var missingCleanups = 0
    missing.onSignedOut = { missingCleanups += 1 }
    await missing.restore()
    await missing.signOut()
    #expect(missingCleanups == 1)
  }

  @Test func restoreWhileSignedInKeepsTheSession() async {
    client.respond { _ in FakeAPIClient.json(Fixtures.user) }
    let store = makeStore()
    await store.restore()
    client.respond { _ throws(APIError) in throw .unauthorized }
    var signedOut = 0
    store.onSignedOut = { signedOut += 1 }
    await store.restore()
    #expect(store.phase == .signedIn(Fixtures.user))
    #expect(signedOut == 0)
    #expect(client.calls.count == 1)
  }

  @Test func restoreOfflineKeepsTheSessionAndOffersRetry() async {
    client.respond { _ throws(APIError) in throw .offline }
    let store = makeStore()
    await store.restore()
    #expect(store.phase == .restoring)
    #expect(store.restoreError == .offline)

    client.respond { _ in FakeAPIClient.json(Fixtures.user) }
    await store.restore()
    #expect(store.phase == .signedIn(Fixtures.user))
    #expect(store.restoreError == nil)
  }

  @Test func signInReturnsNilAndLoadsTheUser() async throws {
    client.respond { _ in FakeAPIClient.json(Fixtures.user) }
    let store = makeStore(token: nil)
    let message = await store.signIn(server: try #require(server), username: "ana", password: "secret")
    #expect(message == nil)
    #expect(store.phase == .signedIn(Fixtures.user))
    #expect(client.calls.map(\.path) == ["/api/login", "/api/me"])
  }

  @Test func signInFailureReturnsTheServerMessage() async throws {
    client.failSignIn(with: .server(status: 401, message: "usuário ou senha inválidos", code: nil, retry: nil))
    let store = makeStore(token: nil)
    let message = await store.signIn(server: try #require(server), username: "ana", password: "x")
    #expect(message == "usuário ou senha inválidos")
    #expect(store.user == nil)
  }

  @Test func signOutCallsLogoutAndNotifies() async {
    client.respond { _ in FakeAPIClient.json(Fixtures.user) }
    let store = makeStore()
    var signedOut = 0
    store.onSignedOut = { signedOut += 1 }
    await store.restore()
    await store.signOut()
    #expect(store.phase == .signedOut(message: nil))
    #expect(client.signOutCount == 1)
    #expect(signedOut == 1)
  }

  @Test func invalidateOnlyLeavesASignedInSession() async {
    let store = makeStore()
    var signedOut = 0
    store.onSignedOut = { signedOut += 1 }
    store.invalidate()
    #expect(signedOut == 0)

    client.respond { _ in FakeAPIClient.json(Fixtures.user) }
    await store.restore()
    store.invalidate()
    store.invalidate()
    #expect(store.phase == .signedOut(message: "Sua sessão expirou. Entre de novo."))
    #expect(signedOut == 1)
  }

  @Test func sessionAwareClientInvalidatesOnUnauthorized() async {
    client.respond { _ in FakeAPIClient.json(Fixtures.user) }
    let store = makeStore()
    await store.restore()
    let wrapped = SessionAwareClient(client) { store.invalidate() }

    client.respond { _ throws(APIError) in throw .offline }
    await #expect(throws: APIError.offline) { try await wrapped.send(CoreEndpoints.state) }
    #expect(store.user != nil)

    client.respond { _ throws(APIError) in throw .unauthorized }
    await #expect(throws: APIError.unauthorized) { try await wrapped.send(CoreEndpoints.state) }
    #expect(store.phase == .signedOut(message: SessionStore.expiredMessage))
  }
}
