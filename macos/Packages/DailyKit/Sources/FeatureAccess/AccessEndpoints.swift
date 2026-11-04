import DailyAPI
import DailyModels
import Foundation

/// The calls of the access screen (`app/api/agent-access/**`).
nonisolated enum AccessEndpoints {
  struct CreateTokenBody: Encodable, Sendable, Equatable {
    var label: String
    var scopes: [String]
  }

  static let tokens = Endpoint<APICredentialsResponse>(.get, "/api/agent-access/tokens")

  /// 201 with the secret, shown once (`lib/access/credentials.ts:11`).
  static func createToken(label: String, permission: AccessPermission) -> Endpoint<CreatedAPICredential> {
    Endpoint(
      .post, "/api/agent-access/tokens", body: CreateTokenBody(label: label, scopes: permission.scopes))
  }

  /// 204 on success.
  static func revokeToken(id: String) -> Endpoint<EmptyResponse> {
    Endpoint(.delete, "/api/agent-access/tokens/\(Endpoint<EmptyResponse>.segment(id))")
  }

  static let prompt = Endpoint<AgentAccessPrompt>(.get, "/api/agent-access/prompt")

  /// 503 when the server has no OAuth configured.
  static let config = Endpoint<AgentAccessConfig>(.get, "/api/agent-access/config")

  static let grants = Endpoint<OAuthGrantsResponse>(.get, "/api/agent-access/grants")

  static func revokeGrant(id: String) -> Endpoint<EmptyResponse> {
    Endpoint(.delete, "/api/agent-access/grants/\(Endpoint<EmptyResponse>.segment(id))")
  }
}
