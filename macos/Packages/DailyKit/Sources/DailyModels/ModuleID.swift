/// A dashboard module id (`lib/modules.ts:6-8`). A struct rather than an enum so
/// a module added on the server decodes instead of failing the whole state.
public struct ModuleID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String { rawValue }

  public static let email = ModuleID(rawValue: "email")
  public static let agenda = ModuleID(rawValue: "agenda")
  public static let jira = ModuleID(rawValue: "jira")
  public static let pulls = ModuleID(rawValue: "pulls")
  public static let tasks = ModuleID(rawValue: "tasks")
  public static let notes = ModuleID(rawValue: "notes")
  public static let slack = ModuleID(rawValue: "slack")

  /// The order the web lists panels in (`components/dashboard/useDashboardPanels.tsx:50-139`).
  public static let known: [ModuleID] = [.email, .tasks, .notes, .agenda, .jira, .pulls, .slack]
}
