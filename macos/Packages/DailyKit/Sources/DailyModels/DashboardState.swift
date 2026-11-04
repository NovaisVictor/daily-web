// FROZEN NAME (T006): `DashboardState` and the properties declared here are used
// by the shell and core. T101 adds every remaining key of `lib/types.ts:418-472`
// to this type; it must not rename or remove these.

/// The whole dashboard, as `GET /api/state` returns it.
public struct DashboardState: Codable, Sendable, Equatable {
  public var updatedAt: String
  public var modules: [ModuleID]

  public init(updatedAt: String, modules: [ModuleID]) {
    self.updatedAt = updatedAt
    self.modules = modules
  }
}
