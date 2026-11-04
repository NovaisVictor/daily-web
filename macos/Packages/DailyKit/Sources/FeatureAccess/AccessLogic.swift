import DailyAPI
import DailyModels
import Foundation
import os

nonisolated extension Logger {
  static let access = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureAccess")
}

/// The permission picker of the token form (`AccessPanel.tsx:45`).
nonisolated enum AccessPermission: String, CaseIterable, Sendable, Equatable {
  case report
  case read

  var label: String {
    switch self {
    case .report: "Consultar e reportar tarefas"
    case .read: "Somente consultar"
    }
  }

  /// `scopes` of `POST /api/agent-access/tokens` (`AccessPanel.tsx:27`).
  var scopes: [String] {
    switch self {
    case .report: ["agents:read", "agents:write"]
    case .read: ["agents:read"]
    }
  }
}

nonisolated enum AccessLogic {
  /// `nam_label` limit (`lib/access/credentials.ts:11`).
  static let labelMax = 80

  /// What a token may do, as the list says it (`AccessPanel.tsx:48`).
  static func scopeSummary(_ scopes: [String]) -> String {
    scopes.contains("agents:write") ? "Consulta e envio" : "Somente consulta"
  }

  /// The MCP address, or nil when it is not a plain `http(s)://host/mcp`
  /// (`McpEndpoint`, `AccessPanel.tsx:88-92`).
  static func mcpEndpoint(_ text: String) -> String? {
    guard let url = URLComponents(string: text), let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme), url.host?.isEmpty == false, url.path == "/mcp",
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
    else { return nil }
    return url.string
  }

  /// `accessRequest` (`components/agents/request.ts`): the agent-access routes
  /// answer English codes, so the web shows its own words.
  static func message(_ error: APIError) -> String {
    guard case .server(let status, _, _, _) = error else { return error.userMessage }
    switch status {
    case 409: return "O item mudou. Atualize os dados antes de tentar novamente."
    case 404: return "Este item não está mais disponível."
    case 503: return "O acesso dos agentes ainda não está configurado neste servidor."
    default: return "Não foi possível concluir a operação. Tente novamente."
    }
  }

  /// `formatTime` (`components/agents/contracts.ts:153-156`): pt-BR short date and time.
  static func formatTime(_ text: String, timeZone: TimeZone = .current) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var parsed = formatter.date(from: text)
    if parsed == nil {
      formatter.formatOptions = [.withInternetDateTime]
      parsed = formatter.date(from: text)
    }
    guard let date = parsed else { return text }
    let style = Date.FormatStyle(
      date: .numeric, time: .shortened, locale: Locale(identifier: "pt_BR"), timeZone: timeZone
    )
    .day(.twoDigits).month(.twoDigits).year(.defaultDigits)
    return date.formatted(style)
  }
}
