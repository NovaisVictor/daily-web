import DailyCore
import DailyModels
import Foundation
import os

/// Canned answers for the preview; the labels are made up.
enum AccessPreview {
  static var client: PreviewAPIClient {
    var responses: [String: Data] = [:]
    let encoder = JSONEncoder()
    do {
      responses["GET /api/agent-access/tokens"] = try encoder.encode(
        APICredentialsResponse(items: [
          APICredential(
            id: "c1", label: "Claude no notebook", prefix: "dwp_AbCdEfGh", scopes: ["agents:read", "agents:write"],
            state: .active, createdAt: "2026-11-01T10:00:00.000Z", lastUsedAt: "2026-11-04T12:00:00.000Z")
        ]))
      responses["GET /api/agent-access/prompt"] = try encoder.encode(
        AgentAccessPrompt(prompt: "Track your work in Daily Web at https://daily.example.com."))
      responses["GET /api/agent-access/config"] = try encoder.encode(
        AgentAccessConfig(mcpUrl: "https://daily.example.com/mcp"))
      responses["GET /api/agent-access/grants"] = try encoder.encode(OAuthGrantsResponse(grants: []))
    } catch {
      Logger.access.fault("Preview data failed to encode: \(String(describing: error), privacy: .public)")
    }
    return PreviewAPIClient(responses: responses)
  }
}
