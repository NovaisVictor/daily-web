import DailyAPI
import DailyModels
import Foundation
import Observation
import os

/// The "Disposição dos painéis" section (`components/LayoutPanel.tsx`): whether
/// the Home grid still has the server's default layout, and the restore.
@Observable
final class LayoutStore {
  enum Status: Equatable {
    /// The default or the dashboard state has not arrived yet.
    case unknown
    case isDefault
    case customized
  }

  /// The server's default, read once; the web asks the server instead of
  /// duplicating `defaultLayout()` in the client.
  private(set) var defaultLayout: [LayoutItem]?
  private(set) var isRestoring = false
  private(set) var error: String?

  @ObservationIgnored private let client: any APIClient
  /// Reads the dashboard again, so the Home grid and this section see the reset.
  @ObservationIgnored private let reloadDashboard: () async -> Void

  init(client: any APIClient, reloadDashboard: @escaping () async -> Void) {
    self.client = client
    self.reloadDashboard = reloadDashboard
  }

  /// Compares the whole array, order included, as the web's
  /// `JSON.stringify(estado.layout) === JSON.stringify(padrao.layout)` does.
  func status(current: [LayoutItem]?) -> Status {
    guard let defaultLayout, let current else { return .unknown }
    return current == defaultLayout ? .isDefault : .customized
  }

  func load() async {
    do {
      defaultLayout = try await client.send(LayoutEndpoints.layoutDefault).layout
      error = nil
    } catch {
      if case .cancelled = error { return }
      Logger.settings.error("Default layout load failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }

  /// `PATCH {layout: null}`, then a fresh `GET /api/state`: the status follows
  /// the dashboard, so it turns to "default" once the new state arrives.
  func restore() async {
    isRestoring = true
    defer { isRestoring = false }
    do {
      _ = try await client.send(LayoutEndpoints.reset)
      error = nil
    } catch {
      Logger.settings.error("Layout restore failed: \(String(describing: error), privacy: .public)")
      // `LayoutPanel.tsx:46`.
      self.error = "Falha ao restaurar a disposição"
      return
    }
    await reloadDashboard()
  }
}
