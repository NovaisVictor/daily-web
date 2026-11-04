import DailyModels
import Foundation

/// The connection form, generated from the server's catalog (`ModuleSpec`)
/// with the rules of `lib/modules.ts` and `components/IntegrationsPanel.tsx`.
enum IntegrationForm {
  /// `MAIL_PRESETS` (`lib/modules.ts:57-73`). The catalog does not carry them,
  /// so they are copied here.
  static let mailPresets: [String: [String: String]] = [
    "gmail": ["imapHost": "imap.gmail.com", "imapPort": "993", "smtpHost": "smtp.gmail.com", "smtpPort": "465"],
    "outlook": [
      "imapHost": "outlook.office365.com", "imapPort": "993", "smtpHost": "smtp.office365.com", "smtpPort": "587",
    ],
    "icloud": ["imapHost": "imap.mail.me.com", "imapPort": "993", "smtpHost": "smtp.mail.me.com", "smtpPort": "587"],
    "yahoo": [
      "imapHost": "imap.mail.yahoo.com", "imapPort": "993", "smtpHost": "smtp.mail.yahoo.com", "smtpPort": "465",
    ],
    "fastmail": [
      "imapHost": "imap.fastmail.com", "imapPort": "993", "smtpHost": "smtp.fastmail.com", "smtpPort": "465",
    ],
  ]

  /// Shown instead of the placeholder when a secret is already saved: a saved
  /// secret never comes back, and blank keeps it (`IntegrationsPanel.tsx:109-114`).
  static let savedSecretPlaceholder = "•••••••• (guardado — deixe em branco para manter)"

  /// `defaultsFor`.
  static func defaults(for spec: ModuleSpec) -> [String: String] {
    var values: [String: String] = [:]
    for field in spec.fields {
      if let value = field.defaultValue { values[field.name] = value }
    }
    return values
  }

  /// `visibleFields`: hidden fields never show, and a `showWhen` field only
  /// when the other field (or its default) has one of the listed values.
  static func visibleFields(_ spec: ModuleSpec, values: [String: String]) -> [FieldSpec] {
    let defaults = defaults(for: spec)
    return spec.fields.filter { field in
      if field.hidden == true { return false }
      guard let condition = field.showWhen else { return true }
      let current = values[condition.field] ?? defaults[condition.field] ?? ""
      return condition.equals.contains(current)
    }
  }

  /// `applyMailPreset`: fills host and port from the provider without
  /// replacing what the person typed.
  static func applyMailPreset(_ values: [String: String]) -> [String: String] {
    guard let preset = mailPresets[values["preset"] ?? ""] else { return values }
    return preset.merging(values) { _, typed in typed }
  }

  /// Sets one field, applying the mail preset when the provider changes.
  static func setting(_ name: String, to value: String, in values: [String: String]) -> [String: String] {
    var next = values
    next[name] = value
    return name == "preset" ? applyMailPreset(next) : next
  }

  /// A provider that is not installed is not offered: picking it leads to an
  /// error the screen cannot fix (`IntegrationsPanel.tsx:85-89`).
  static func options(for field: FieldSpec, mstodoAvailable: Bool) -> [FieldOption] {
    (field.options ?? []).filter { $0.value != "mstodo" || mstodoAvailable }
  }

  static func placeholder(for field: FieldSpec, alreadySet: Bool) -> String? {
    alreadySet && field.secret == true ? savedSecretPlaceholder : field.placeholder
  }

  /// `validateValues` (`lib/modules.ts:340-349`), the server's own check and
  /// texts. On an edit a saved secret left blank counts as filled, as the
  /// server merges what it has.
  static func validate(_ spec: ModuleSpec, values: [String: String], savedSecrets: Set<String> = []) -> [String] {
    let merged = defaults(for: spec).merging(values) { _, value in value }
    return visibleFields(spec, values: merged)
      .filter { field in
        guard field.required == true else { return false }
        if savedSecrets.contains(field.name) { return false }
        return (merged[field.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      .map { "\($0.label) é obrigatório" }
  }

  /// Only what the form shows goes in the body: hidden fields belong to the
  /// server (`IntegrationsPanel.tsx:233-240`).
  static func body(_ spec: ModuleSpec, values: [String: String], label: String) -> IntegrationsEndpoints.ConnectionBody
  {
    let allowed = Set(visibleFields(spec, values: values).map(\.name))
    return IntegrationsEndpoints.ConnectionBody(label: label, values: values.filter { allowed.contains($0.key) })
  }

  /// The one connect action of a module's details (`IntegrationsPanel.tsx:356-397`).
  enum ConnectAction: Equatable {
    /// Opens the server's OAuth start in the browser.
    case browser(title: String, path: String, query: [URLQueryItem])
    /// Opens the generated form for a new connection.
    case form(title: String)
  }

  static func connectAction(
    for module: ModuleState,
    spec: ModuleSpec,
    payload: IntegrationsPayload
  ) -> ConnectAction? {
    let connected = !module.connections.isEmpty
    if module.module == .slack, payload.slackConfigured {
      return .browser(title: connected ? "Reconectar" : "Conectar", path: "/api/integrations/slack/start", query: [])
    }
    if module.module == .agenda, payload.googleConfigured {
      return .browser(
        title: connected ? "Adicionar outra" : "Conectar", path: "/api/integrations/agenda/google/start", query: [])
    }
    // The Drive copy of the notes only comes from Google, one per person.
    if module.module == .notes, payload.googleConfigured, !connected {
      return .browser(
        title: "Conectar", path: "/api/integrations/agenda/google/start",
        query: [URLQueryItem(name: "purpose", value: "notes")])
    }
    if hasVisibleFields(spec), spec.multi || !connected {
      return .form(title: connected ? "Adicionar outra" : "Conectar")
    }
    return nil
  }

  static func hasVisibleFields(_ spec: ModuleSpec) -> Bool {
    spec.fields.contains { $0.hidden != true }
  }

  /// A Google connection is managed by its calendars, not by the form.
  static func isGoogle(_ connection: ConnectionSummary) -> Bool {
    connection.visible["provider"] == "google"
  }

  /// What the row says under the connection's name (`IntegrationsPanel.tsx:465-472`).
  static func subtitle(_ connection: ConnectionSummary, spec: ModuleSpec?) -> String {
    if connection.unreadable { return "ilegível com a chave atual — grave de novo" }
    // The web shows the first visible value in the catalog's declaration order.
    let ordered = (spec?.fields ?? []).compactMap { connection.visible[$0.name] }
    return ordered.first ?? connection.visible.sorted { $0.key < $1.key }.first?.value ?? "configurado"
  }

  /// `<server>/<path>?<query>`: the OAuth flows run in the browser, whose own
  /// session finishes them.
  static func serverURL(_ server: URL?, path: String, query: [URLQueryItem]) -> URL? {
    guard let server, var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
    components.path = path
    components.queryItems = query.isEmpty ? nil : query
    return components.url
  }
}
