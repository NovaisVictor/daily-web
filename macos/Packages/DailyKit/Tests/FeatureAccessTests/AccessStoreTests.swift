import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Testing

@testable import FeatureAccess

nonisolated let credential = APICredential(
  id: "c1", label: "Claude no notebook", prefix: "dwp_AbCdEfGh", scopes: ["agents:read", "agents:write"],
  state: .active, createdAt: "2026-11-01T10:00:00.000Z", lastUsedAt: nil)
nonisolated let grant = OAuthGrant(
  id: "g1", clientId: "client", clientName: "Cliente MCP", scopes: ["tasks"], expiresAt: nil)

nonisolated func answer(_ call: FakeAPIClient.Call) throws(APIError) -> Data {
  switch (call.method, call.path) {
  case ("GET", "/api/agent-access/tokens"): return FakeAPIClient.json(APICredentialsResponse(items: [credential]))
  case ("POST", "/api/agent-access/tokens"):
    return FakeAPIClient.json(CreatedAPICredential(credential: credential, secret: "dwp_secret"))
  case ("GET", "/api/agent-access/prompt"): return FakeAPIClient.json(AgentAccessPrompt(prompt: "Track your work"))
  case ("GET", "/api/agent-access/config"):
    return FakeAPIClient.json(AgentAccessConfig(mcpUrl: "http://localhost:8010/mcp"))
  case ("GET", "/api/agent-access/grants"): return FakeAPIClient.json(OAuthGrantsResponse(grants: [grant]))
  default: return FakeAPIClient.ok
  }
}

@Suite struct AccessLogicTests {
  @Test func permissionMapsToScopes() {
    #expect(AccessPermission.report.scopes == ["agents:read", "agents:write"])
    #expect(AccessPermission.read.scopes == ["agents:read"])
    #expect(AccessPermission.report.label == "Consultar e reportar tarefas")
    #expect(AccessPermission.read.label == "Somente consultar")
    #expect(AccessLogic.scopeSummary(["agents:read", "agents:write"]) == "Consulta e envio")
    #expect(AccessLogic.scopeSummary(["agents:read"]) == "Somente consulta")
  }

  @Test func mcpEndpointValidation() {
    #expect(AccessLogic.mcpEndpoint("https://daily.example.com/mcp") == "https://daily.example.com/mcp")
    #expect(AccessLogic.mcpEndpoint("ftp://daily.example.com/mcp") == nil)
    #expect(AccessLogic.mcpEndpoint("https://daily.example.com/other") == nil)
    #expect(AccessLogic.mcpEndpoint("https://u:p@daily.example.com/mcp") == nil)
    #expect(AccessLogic.mcpEndpoint("https://daily.example.com/mcp?x=1") == nil)
  }

  @Test func endpoints() {
    let create = AccessEndpoints.createToken(label: "CI", permission: .read)
    #expect(create.method == .post)
    #expect(create.path == "/api/agent-access/tokens")
    #expect(FakeAPIClient.encode(create.body) == #"{"label":"CI","scopes":["agents:read"]}"#)
    #expect(AccessEndpoints.revokeToken(id: "a/b").method == .delete)
    #expect(AccessEndpoints.revokeToken(id: "a/b").path == "/api/agent-access/tokens/a%2Fb")
    #expect(AccessEndpoints.revokeGrant(id: "g1").path == "/api/agent-access/grants/g1")
    #expect(AccessEndpoints.revokeGrant(id: "g1").method == .delete)
    #expect(AccessEndpoints.prompt.path == "/api/agent-access/prompt")
    #expect(AccessEndpoints.config.path == "/api/agent-access/config")
    #expect(AccessEndpoints.grants.path == "/api/agent-access/grants")
  }
}

@MainActor
@Suite struct AccessStoreTests {
  let client = FakeAPIClient()
  let store: AccessStore

  init() {
    client.respond { call throws(APIError) in try answer(call) }
    store = AccessStore(client: client)
  }

  @Test func loadsEverything() async {
    await store.loadAll()
    #expect(store.tokens == [credential])
    #expect(store.prompt == "Track your work")
    #expect(store.mcpEndpoint == "http://localhost:8010/mcp")
    #expect(store.grants == [grant])
    #expect(store.error == nil)
  }

  @Test func mcpUnavailableShowsTheWebText() async {
    client.respond { _ throws(APIError) in
      throw .server(status: 503, message: "oauth_not_configured", code: nil, retry: nil)
    }
    await store.loadConfig()
    #expect(store.mcpEndpoint == nil)
    #expect(store.mcpError == "O acesso dos agentes ainda não está configurado neste servidor.")
  }

  @Test func createsATokenAndShowsTheSecretOnce() async {
    store.setLabel("Claude no notebook")
    store.permission = .read
    await store.create()
    let post = client.calls.first { $0.method == "POST" }
    #expect(post?.body == #"{"label":"Claude no notebook","scopes":["agents:read"]}"#)
    #expect(store.secret == "dwp_secret")
    #expect(store.label.isEmpty)
    #expect(client.calls.last?.path == "/api/agent-access/tokens")
    store.dismissSecret()
    #expect(store.secret == nil)
  }

  @Test func createFailureKeepsTheForm() async {
    client.respond { _ throws(APIError) in throw .server(status: 400, message: "Invalid label", code: nil, retry: nil) }
    store.setLabel("CI")
    await store.create()
    #expect(store.secret == nil)
    #expect(store.label == "CI")
    #expect(store.error == "Não foi possível concluir a operação. Tente novamente.")
  }

  @Test func labelIsCappedAndRequired() {
    store.setLabel(String(repeating: "a", count: 90))
    #expect(store.label.count == 80)
    store.setLabel("   ")
    #expect(!store.canCreate)
  }

  @Test func revokesATokenAndReloads() async {
    #expect(await store.revoke(credential))
    #expect(
      client.calls.map { "\($0.method) \($0.path)" } == [
        "DELETE /api/agent-access/tokens/c1", "GET /api/agent-access/tokens",
      ])
  }

  @Test func revokeFailureIsShown() async {
    client.respond { _ throws(APIError) in throw .server(status: 404, message: "x", code: nil, retry: nil) }
    #expect(!(await store.revoke(credential)))
    #expect(store.error == "Este item não está mais disponível.")
  }

  @Test func revokesAGrantAndReloads() async {
    #expect(await store.revoke(grant))
    #expect(
      client.calls.map { "\($0.method) \($0.path)" } == [
        "DELETE /api/agent-access/grants/g1", "GET /api/agent-access/grants",
      ])
    client.respond { _ throws(APIError) in throw .server(status: 500, message: "x", code: nil, retry: nil) }
    #expect(!(await store.revoke(grant)))
    #expect(store.grantsError == "Não foi possível concluir a operação. Tente novamente.")
  }
}
