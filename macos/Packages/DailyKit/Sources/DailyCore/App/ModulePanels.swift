import DailyModels
import SwiftUI

/// The full panel of each module (spec 011), provided by the app target so
/// Início can show a feature's panel without importing the feature.
public struct ModulePanels {
  private let make: (ModuleID) -> AnyView?

  public init(make: @escaping (ModuleID) -> AnyView?) {
    self.make = make
  }

  /// The module's panel, or nil when the app has none for it.
  public func panel(for module: ModuleID) -> AnyView? {
    make(module)
  }

  /// No panels: previews and tests that don't need them.
  public static let none = ModulePanels { _ in nil }
}

extension EnvironmentValues {
  @Entry public var modulePanels: ModulePanels = .none
}
