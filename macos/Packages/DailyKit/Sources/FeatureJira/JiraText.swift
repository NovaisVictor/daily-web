import DailyCore
import DailyModels
import Foundation

/// Small text helpers the Jira screen shares with the web (`lib/filters.ts`,
/// `lib/parsers/jira.ts`); the row labels it shares with "Hoje" are `JiraFormat`.
nonisolated enum JiraText {
  /// `matchesQuery`, `lib/filters.ts:14-18`: accent- and case-insensitive on both sides.
  static func matches(_ fields: [String], query: String) -> Bool {
    let term = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !term.isEmpty else { return true }
    return fields.contains { normalize($0).contains(term) }
  }

  static func normalize(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive], locale: nil).lowercased()
  }

  /// `String.prototype.localeCompare` in pt-BR, for the sorted option lists.
  static func localeLess(_ lhs: String, _ rhs: String) -> Bool {
    lhs.compare(rhs, locale: ptBR) == .orderedAscending
  }

  static let ptBR = Locale(identifier: "pt_BR")

  /// `isJiraKey`, `lib/jiraKey.ts`: letters, a hyphen, digits.
  static func isJiraKey(_ value: String) -> Bool {
    value.uppercased().wholeMatch(of: /[A-Z][A-Z0-9_]*-\d+/) != nil
  }

  /// `typeMarker`, `lib/parsers/jira.ts:3-17`.
  static func typeMarker(_ kind: String) -> String {
    typeMarkers[kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? "[?]"
  }

  static func issueMarker(_ item: JiraItem) -> String {
    item.subtask ? "[s]" : typeMarker(item.kind)
  }

  /// `isEpic`, `lib/parsers/jiraProblems.ts:16`: the same mapping that draws the marker.
  static func isEpic(_ item: JiraItem) -> Bool { issueMarker(item) == "[E]" }

  private static let typeMarkers: [String: String] = [
    "história": "[S]", "historia": "[S]", "story": "[S]",
    "epic": "[E]", "épico": "[E]", "epico": "[E]",
    "iniciativa": "[I]", "initiative": "[I]",
    "objetivo": "[O]", "objective": "[O]",
    "[system] service request": "[R]", "service request": "[R]",
    "solicitação de serviço": "[R]", "solicitacao de servico": "[R]",
    "pedido de serviço": "[R]", "pedido de servico": "[R]",
    "requisição": "[R]", "requisicao": "[R]",
  ]

  /// `BASIS_NOTE`, `components/JiraProblemFix.tsx:13-17`.
  static func basisNote(_ basis: JiraStartDateBasis) -> String? {
    switch basis {
    case .started: "primeira passagem por andamento"
    case .finished: "foi do Backlog direto para concluída: dia da conclusão"
    case .created: "criada já fora do Backlog: dia da criação"
    default: nil
    }
  }

  /// `formatDate`, `components/jira/actions/EditActions.tsx:36-39`.
  static func formatDate(_ iso: String) -> String {
    guard let (year, month, day) = JiraDates.calendarParts(iso) else { return "sem prazo" }
    return String(format: "%02d/%02d/%04d", day, month, year)
  }
}
