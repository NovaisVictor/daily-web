/// The input a connection field asks for (`lib/modules.ts:10`).
public struct FieldType: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let text = FieldType(rawValue: "text")
  public static let password = FieldType(rawValue: "password")
  public static let url = FieldType(rawValue: "url")
  public static let number = FieldType(rawValue: "number")
  public static let select = FieldType(rawValue: "select")
  public static let known: [FieldType] = [.text, .password, .url, .number, .select]
}

/// One choice of a `select` field (`lib/modules.ts:21`).
public struct FieldOption: Codable, Sendable, Equatable, Hashable {
  public var value: String
  public var label: String

  public init(value: String, label: String) {
    self.value = value
    self.label = label
  }
}

/// Show the field only when another field has one of these values (`lib/modules.ts:24`).
public struct FieldCondition: Codable, Sendable, Equatable, Hashable {
  public var field: String
  public var equals: [String]

  public init(field: String, equals: [String]) {
    self.field = field
    self.equals = equals
  }
}

/// A connection form field (`lib/modules.ts:12-32`). The flags are absent
/// rather than false when unset.
public struct FieldSpec: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var name: String
  public var label: String
  public var type: FieldType
  /// Never sent back once saved.
  public var secret: Bool?
  public var `required`: Bool?
  public var placeholder: String?
  public var help: String?
  public var options: [FieldOption]?
  public var defaultValue: String?
  public var showWhen: FieldCondition?
  /// Kept by the connection but never shown by the form.
  public var hidden: Bool?

  public var id: String { name }

  public init(
    name: String,
    label: String,
    type: FieldType,
    secret: Bool? = nil,
    required: Bool? = nil,
    placeholder: String? = nil,
    help: String? = nil,
    options: [FieldOption]? = nil,
    defaultValue: String? = nil,
    showWhen: FieldCondition? = nil,
    hidden: Bool? = nil
  ) {
    self.name = name
    self.label = label
    self.type = type
    self.secret = secret
    self.required = required
    self.placeholder = placeholder
    self.help = help
    self.options = options
    self.defaultValue = defaultValue
    self.showWhen = showWhen
    self.hidden = hidden
  }
}

/// A module of the catalog (`lib/modules.ts:34-46`).
public struct ModuleSpec: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: ModuleID
  public var label: String
  public var summary: String
  /// Several connections (mailboxes, calendars) or just one.
  public var multi: Bool
  /// Works without credentials, so it is on from the first login.
  public var alwaysAvailable: Bool?
  public var instructions: [String]
  public var fields: [FieldSpec]

  public init(
    id: ModuleID,
    label: String,
    summary: String,
    multi: Bool,
    alwaysAvailable: Bool? = nil,
    instructions: [String],
    fields: [FieldSpec]
  ) {
    self.id = id
    self.label = label
    self.summary = summary
    self.multi = multi
    self.alwaysAvailable = alwaysAvailable
    self.instructions = instructions
    self.fields = fields
  }
}

/// A saved connection as the settings screen sees it, never with a secret
/// value (`lib/vault/connections.ts:14-24`).
public struct ConnectionSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var module: ModuleID
  public var label: String
  public var visible: [String: String]
  /// Names of the secret fields already saved.
  public var secretsSet: [String]
  public var updatedAt: String
  /// The credential could not be decrypted (key changed or record corrupted).
  public var unreadable: Bool

  public init(
    id: String,
    module: ModuleID,
    label: String,
    visible: [String: String],
    secretsSet: [String],
    updatedAt: String,
    unreadable: Bool
  ) {
    self.id = id
    self.module = module
    self.label = label
    self.visible = visible
    self.secretsSet = secretsSet
    self.updatedAt = updatedAt
    self.unreadable = unreadable
  }
}

/// One module for this user (`lib/vault/connections.ts:26-34`).
public struct ModuleState: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var module: ModuleID
  public var label: String
  public var summary: String
  public var multi: Bool
  public var enabled: Bool
  public var configured: Bool
  public var connections: [ConnectionSummary]

  public var id: ModuleID { module }

  public init(
    module: ModuleID,
    label: String,
    summary: String,
    multi: Bool,
    enabled: Bool,
    configured: Bool,
    connections: [ConnectionSummary]
  ) {
    self.module = module
    self.label = label
    self.summary = summary
    self.multi = multi
    self.enabled = enabled
    self.configured = configured
    self.connections = connections
  }
}

/// `GET /api/integrations` (`app/api/integrations/route.ts:14-31`). `catalog`
/// is `Record<ModuleId, ModuleSpec>`, keyed by the module id's raw value.
public struct IntegrationsPayload: Codable, Sendable, Equatable, Hashable {
  public var vaultReady: Bool
  public var mstodoAvailable: Bool
  public var googleConfigured: Bool
  public var googleRedirectUri: String
  public var slackConfigured: Bool
  public var slackRedirectUri: String
  public var catalog: [String: ModuleSpec]
  public var modules: [ModuleState]

  public init(
    vaultReady: Bool,
    mstodoAvailable: Bool,
    googleConfigured: Bool,
    googleRedirectUri: String,
    slackConfigured: Bool,
    slackRedirectUri: String,
    catalog: [String: ModuleSpec],
    modules: [ModuleState]
  ) {
    self.vaultReady = vaultReady
    self.mstodoAvailable = mstodoAvailable
    self.googleConfigured = googleConfigured
    self.googleRedirectUri = googleRedirectUri
    self.slackConfigured = slackConfigured
    self.slackRedirectUri = slackRedirectUri
    self.catalog = catalog
    self.modules = modules
  }

  public func spec(for module: ModuleID) -> ModuleSpec? {
    catalog[module.rawValue]
  }
}

/// `PATCH /api/integrations/{module}`, the connection writes and
/// `PATCH /api/integrations/agenda/google/calendars`
/// (`app/api/integrations/[module]/route.ts:28`, `…/connections/route.ts:49`,
/// `…/connections/[id]/route.ts:40`, `…/agenda/google/calendars/route.ts:42`).
public struct ModulesResponse: Codable, Sendable, Equatable, Hashable {
  public var modules: [ModuleState]

  public init(modules: [ModuleState]) {
    self.modules = modules
  }
}

/// `DELETE /api/integrations/{module}/connections/{id}`
/// (`app/api/integrations/[module]/connections/[id]/route.ts:58`): `label` is
/// the module's label, for the confirmation toast.
public struct ConnectionRemovedResponse: Codable, Sendable, Equatable, Hashable {
  public var modules: [ModuleState]
  public var label: String

  public init(modules: [ModuleState], label: String) {
    self.modules = modules
    self.label = label
  }
}

/// `POST /api/integrations/{module}/test`, always 200
/// (`app/api/integrations/[module]/test/route.ts:42-53`).
public struct ConnectionTestResult: Codable, Sendable, Equatable, Hashable {
  public var ok: Bool
  public var message: String

  public init(ok: Bool, message: String) {
    self.ok = ok
    self.message = message
  }
}

/// A Google calendar the account can read (`lib/integrations/google/calendar.ts:10-14`).
public struct CalendarRef: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var label: String
  public var primary: Bool

  public init(id: String, label: String, primary: Bool) {
    self.id = id
    self.label = label
    self.primary = primary
  }
}

/// `GET /api/integrations/agenda/google/calendars`
/// (`app/api/integrations/agenda/google/calendars/route.ts:14-17`).
public struct GoogleCalendarsResponse: Codable, Sendable, Equatable, Hashable {
  public var calendars: [CalendarRef]
  /// Ids of the chosen calendars.
  public var selected: [String]

  public init(calendars: [CalendarRef], selected: [String]) {
    self.calendars = calendars
    self.selected = selected
  }
}
