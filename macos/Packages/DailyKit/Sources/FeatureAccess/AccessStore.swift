import DailyAPI
import DailyCore
import DailyModels
import Foundation
import Observation
import os

/// State and actions of "Acesso dos agentes" (`components/agents/AccessPanel.tsx`).
@Observable
final class AccessStore {
  // MARK: Tokens

  private(set) var tokens: [APICredential]?
  /// Load, create and revoke share one message, as on the web (`AccessPanel.tsx:31`).
  private(set) var error: String?
  var label = ""
  var permission: AccessPermission = .report
  private(set) var isSaving = false
  /// The new token's secret, until the user says it is saved. Never kept anywhere else.
  private(set) var secret: String?

  // MARK: Prompt and MCP

  private(set) var prompt: String?
  private(set) var promptError: String?
  private(set) var mcpEndpoint: String?
  private(set) var mcpError: String?

  // MARK: OAuth grants

  private(set) var grants: [OAuthGrant]?
  private(set) var grantsError: String?
  private(set) var isRevokingGrant = false

  @ObservationIgnored private let client: any APIClient

  init(client: any APIClient) {
    self.client = client
  }

  var canCreate: Bool {
    !isSaving && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func setLabel(_ value: String) {
    label = String(value.prefix(AccessLogic.labelMax))
  }

  /// Everything the screen reads, in parallel.
  func loadAll() async {
    async let tokens: Void = loadTokens()
    async let prompt: Void = loadPrompt()
    async let config: Void = loadConfig()
    async let grants: Void = loadGrants()
    _ = await (tokens, prompt, config, grants)
  }

  func loadTokens() async {
    do {
      tokens = try await client.send(AccessEndpoints.tokens).items
      error = nil
    } catch {
      Logger.access.error("Token list failed: \(String(describing: error), privacy: .public)")
      self.error = AccessLogic.message(error)
    }
  }

  func loadPrompt() async {
    do {
      prompt = try await client.send(AccessEndpoints.prompt).prompt
      promptError = nil
    } catch {
      Logger.access.error("Prompt load failed: \(String(describing: error), privacy: .public)")
      promptError = AccessLogic.message(error)
    }
  }

  /// A 503 means the server has no OAuth; the web then shows its message
  /// in place of the address.
  func loadConfig() async {
    do {
      let config = try await client.send(AccessEndpoints.config)
      guard let endpoint = AccessLogic.mcpEndpoint(config.mcpUrl) else {
        mcpEndpoint = nil
        mcpError = "Endereço MCP inválido."
        return
      }
      mcpEndpoint = endpoint
      mcpError = nil
    } catch {
      Logger.access.error("MCP config load failed: \(String(describing: error), privacy: .public)")
      mcpEndpoint = nil
      mcpError = AccessLogic.message(error)
    }
  }

  func loadGrants() async {
    do {
      grants = try await client.send(AccessEndpoints.grants).grants
      grantsError = nil
    } catch {
      Logger.access.error("Grant list failed: \(String(describing: error), privacy: .public)")
      grantsError = AccessLogic.message(error)
    }
  }

  // MARK: - Actions

  /// "Gerar token": on success the secret is shown once and the form clears.
  func create() async {
    let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !isSaving, !name.isEmpty else { return }
    isSaving = true
    error = nil
    defer { isSaving = false }
    do {
      let created = try await client.send(AccessEndpoints.createToken(label: label, permission: permission))
      guard !created.secret.isEmpty else {
        error = "Não foi possível verificar o acesso criado. Atualize a lista antes de gerar outro."
        return
      }
      secret = created.secret
      label = ""
    } catch {
      Logger.access.error("Token creation failed: \(String(describing: error), privacy: .public)")
      self.error = AccessLogic.message(error)
      return
    }
    await loadTokens()
  }

  /// "Já guardei o token": the secret leaves memory.
  func dismissSecret() {
    secret = nil
  }

  @discardableResult
  func revoke(_ token: APICredential) async -> Bool {
    guard !isSaving else { return false }
    isSaving = true
    error = nil
    defer { isSaving = false }
    do {
      _ = try await client.send(AccessEndpoints.revokeToken(id: token.id))
    } catch {
      Logger.access.error("Token revocation failed: \(String(describing: error), privacy: .public)")
      self.error = AccessLogic.message(error)
      return false
    }
    await loadTokens()
    return true
  }

  @discardableResult
  func revoke(_ grant: OAuthGrant) async -> Bool {
    guard !isRevokingGrant else { return false }
    isRevokingGrant = true
    defer { isRevokingGrant = false }
    do {
      _ = try await client.send(AccessEndpoints.revokeGrant(id: grant.id))
    } catch {
      Logger.access.error("Grant revocation failed: \(String(describing: error), privacy: .public)")
      grantsError = AccessLogic.message(error)
      return false
    }
    await loadGrants()
    return true
  }
}
