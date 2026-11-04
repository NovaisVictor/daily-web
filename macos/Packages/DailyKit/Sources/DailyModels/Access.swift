/// `lib/access/credentials.ts:6`.
public struct APICredentialState: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let active = APICredentialState(rawValue: "active")
  public static let revoked = APICredentialState(rawValue: "revoked")
  public static let known: [APICredentialState] = [.active, .revoked]
}

/// A reporting token, without its secret (`ApiCredential`, `lib/access/credentials.ts:6`).
/// `scopes` are `agents:read` and `agents:write`.
public struct APICredential: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var label: String
  /// The first characters of the secret, to recognise it.
  public var prefix: String
  public var scopes: [String]
  public var state: APICredentialState
  public var createdAt: String
  public var lastUsedAt: String?

  public init(
    id: String,
    label: String,
    prefix: String,
    scopes: [String],
    state: APICredentialState,
    createdAt: String,
    lastUsedAt: String?
  ) {
    self.id = id
    self.label = label
    self.prefix = prefix
    self.scopes = scopes
    self.state = state
    self.createdAt = createdAt
    self.lastUsedAt = lastUsedAt
  }
}

/// `GET /api/agent-access/tokens` (`app/api/agent-access/tokens/route.ts:3`).
public struct APICredentialsResponse: Codable, Sendable, Equatable, Hashable {
  public var items: [APICredential]

  public init(items: [APICredential]) {
    self.items = items
  }
}

/// `POST /api/agent-access/tokens`, status 201 (`lib/access/credentials.ts:11`).
/// The secret is shown once and never again.
public struct CreatedAPICredential: Codable, Sendable, Equatable, Hashable {
  public var credential: APICredential
  public var secret: String

  public init(credential: APICredential, secret: String) {
    self.credential = credential
    self.secret = secret
  }
}

/// `GET /api/agent-access/prompt` (`app/api/agent-access/prompt/route.ts:3`).
public struct AgentAccessPrompt: Codable, Sendable, Equatable, Hashable {
  public var prompt: String

  public init(prompt: String) {
    self.prompt = prompt
  }
}

/// `GET /api/agent-access/config` (`app/api/agent-access/config/route.ts:3`).
public struct AgentAccessConfig: Codable, Sendable, Equatable, Hashable {
  public var mcpUrl: String

  public init(mcpUrl: String) {
    self.mcpUrl = mcpUrl
  }
}

/// An MCP client the user authorized (`lib/access/grants.ts:8`). A grant
/// without expiry has `expiresAt` null.
public struct OAuthGrant: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var clientId: String
  public var clientName: String
  public var scopes: [String]
  public var expiresAt: String?

  public init(id: String, clientId: String, clientName: String, scopes: [String], expiresAt: String?) {
    self.id = id
    self.clientId = clientId
    self.clientName = clientName
    self.scopes = scopes
    self.expiresAt = expiresAt
  }
}

/// `GET /api/agent-access/grants` (`app/api/agent-access/grants/route.ts:3`).
public struct OAuthGrantsResponse: Codable, Sendable, Equatable, Hashable {
  public var grants: [OAuthGrant]

  public init(grants: [OAuthGrant]) {
    self.grants = grants
  }
}
