import CryptoKit
import DailyAPI
import DailyModels
import DailyStorage
import Foundation
import Observation
import os

/// `PATCH /api/preferences` for the home arrangement and
/// `GET /api/preferences/layout-default` (`app/api/preferences/route.ts:60-130`,
/// `app/api/preferences/layout-default/route.ts`).
public nonisolated enum DashboardLayoutEndpoints {
  struct Viewport: Encodable, Sendable {
    let width: Int
    let height: Int
  }

  struct SaveBody: Encodable, Sendable {
    let layout: [LayoutItem]
    let viewport: Viewport
  }

  /// `{"layout": null}`: the key must be present with a null value, which the
  /// synthesized encoding would leave out.
  struct ResetBody: Encodable, Sendable {
    enum CodingKeys: String, CodingKey { case layout }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeNil(forKey: .layout)
    }
  }

  struct HomeViewBody: Encodable, Sendable {
    let homeView: HomeView
  }

  /// Saves `layout` for a window of `width` × `height` (`route.ts:75-88`); the
  /// server answers both the legacy layout and every saved size.
  public static func save(_ layout: [LayoutItem], width: Int, height: Int) -> Endpoint<LayoutResponse> {
    Endpoint(
      .patch, "/api/preferences", body: SaveBody(layout: layout, viewport: Viewport(width: width, height: height)))
  }

  /// Forgets the legacy layout and every saved size (`resetDashboardLayout`, `lib/preferences.ts:136-141`).
  public static var reset: Endpoint<LayoutResponse> {
    Endpoint(.patch, "/api/preferences", body: ResetBody())
  }

  public static func homeView(_ view: HomeView) -> Endpoint<HomeViewResponse> {
    Endpoint(.patch, "/api/preferences", body: HomeViewBody(homeView: view))
  }

  public static var layoutDefault: Endpoint<LayoutDefaultResponse> {
    Endpoint(.get, "/api/preferences/layout-default")
  }
}

/// `GET /api/preferences/layout-default`.
public nonisolated struct LayoutDefaultResponse: Codable, Sendable, Equatable {
  public var layout: [LayoutItem]

  public init(layout: [LayoutItem]) {
    self.layout = layout
  }
}

/// Whose "Abas" arrangement is read or written: one per server and username (DP-3).
public nonisolated struct LayoutAccount: Hashable, Sendable {
  public let origin: ServerOrigin
  public let username: String

  /// Nil for a server without an http(s) origin.
  public init?(server: URL, username: String) {
    guard let origin = ServerOrigin(server) else { return nil }
    self.origin = origin
    self.username = username
  }

  /// Hashed so a username never becomes part of a file name.
  var fileName: String {
    let digest = SHA256.hash(data: Data("\(origin.description)|\(username)".utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "home-workspace-\(hex).json"
  }
}

/// The home arrangement: the grid layouts the web shares through the server
/// (DP-2), the Grade/Abas choice, and the "Abas" document kept on this Mac (DP-3).
///
/// The grid rules (sanitizing, nearest size, moving, compacting) live in
/// `FeatureHome`; this store only reads and writes what the server keeps.
/// Failures stay in the store as text for the home screen to show inline, as
/// the web does (`app/(app)/page.tsx:111-112`), rather than as toasts.
@Observable
public final class DashboardLayoutStore {
  /// The web's fallbacks when the server gives no message (`page.tsx:65,90`, `LayoutPanel.tsx:50`).
  public static let saveGridFallback = "Falha ao guardar a disposição dos painéis"
  public static let homeViewFallback = "Falha ao guardar a disposição do Início"
  public static let resetMessage = "Falha ao restaurar a disposição"

  /// The last grid save failure, for "Não deu para guardar a disposição".
  public private(set) var layoutError: String?
  /// The last Grade/Abas failure, for "Não deu para trocar a disposição".
  public private(set) var viewError: String?
  /// The last "Restaurar disposição padrão" failure.
  public private(set) var resetError: String?
  /// The last failure reading the server's default, shown by Configuração → Disposição.
  public private(set) var checkError: String?
  public private(set) var isSavingGrid = false
  public private(set) var isResettingGrid = false
  /// The server's default grid, once `checkDefaultGrid()` or `resetGrid()` brought it.
  public private(set) var defaultLayout: [LayoutItem]?

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let dashboard: DashboardStore
  /// Where the "Abas" documents live; nil keeps them in memory only (previews, tests).
  @ObservationIgnored private let workspaceDirectory: URL?
  @ObservationIgnored private var memoryWorkspaces: [LayoutAccount: Data] = [:]

  public init(client: any APIClient, dashboard: DashboardStore, workspaceDirectory: URL?) {
    self.client = client
    self.dashboard = dashboard
    self.workspaceDirectory = workspaceDirectory
  }

  /// The session's store, shared by Início and Configuração → Disposição so
  /// both see the same default check and the same saves.
  ///
  /// - Parameter workspaceDirectory: Where the "Abas" arrangement is kept; nil
  ///   keeps it in memory (previews). Only the first call's value counts.
  public static func shared(
    in environment: AppEnvironment, workspaceDirectory: URL? = AppEnvironment.defaultCacheDirectory
  ) -> DashboardLayoutStore {
    environment.featureStores.store(storeKey) {
      DashboardLayoutStore(
        client: environment.client, dashboard: environment.dashboard, workspaceDirectory: workspaceDirectory)
    }
  }

  static let storeKey = "dashboardLayout"

  // MARK: - What the server keeps

  /// The single legacy layout, used when no size was saved (`page.tsx:33`).
  public var layout: [LayoutItem] { dashboard.state?.layout ?? [] }
  /// The layouts saved per window size, newest first.
  public var layouts: [SavedLayout] { dashboard.state?.layouts ?? [] }
  /// A state cached before this preference existed has none; the grid is the default (`page.tsx:29-30`).
  public var homeView: HomeView { dashboard.state?.homeView ?? .grid }

  /// Whether the grid is in the default arrangement; nil until the default
  /// arrived. It follows the dashboard, so a save from the grid shows at once.
  /// Unlike the web, a layout saved for some window size also counts as a
  /// change: since sizes are saved, the legacy layout alone stays default.
  public var isDefaultGrid: Bool? {
    guard let defaultLayout, dashboard.state != nil else { return nil }
    return layout == defaultLayout && layouts.isEmpty
  }

  // MARK: - Grid

  /// Saves `layout` for the current window size (`page.tsx:55-74`). Only the
  /// explicit "Salvar para esta tela" calls this; dragging saves nothing.
  @discardableResult
  public func saveGrid(_ layout: [LayoutItem], viewport: CGSize) async -> APIError? {
    isSavingGrid = true
    defer { isSavingGrid = false }
    let width = Int((viewport.width).rounded())
    let height = Int((viewport.height).rounded())
    do {
      let response = try await client.send(DashboardLayoutEndpoints.save(layout, width: width, height: height))
      layoutError = nil
      dashboard.patch {
        $0.layout = response.layout
        $0.layouts = response.layouts
      }
      return nil
    } catch {
      Logger.core.error("Grid layout save failed: \(String(describing: error), privacy: .public)")
      layoutError = Self.text(for: error, fallback: Self.saveGridFallback)
      // The web reloads so the grid shows what the server really keeps.
      await dashboard.reload()
      return error
    }
  }

  /// Asks the server for the default (`LayoutPanel.tsx:18-37`); the web asks
  /// instead of duplicating `defaultLayout()` in the client.
  @discardableResult
  public func checkDefaultGrid() async -> APIError? {
    do {
      defaultLayout = try await client.send(DashboardLayoutEndpoints.layoutDefault).layout
      checkError = nil
      return nil
    } catch {
      // Leaving the screen cancels the request; nothing failed.
      if case .cancelled = error { return error }
      Logger.core.error("Default layout check failed: \(String(describing: error), privacy: .public)")
      checkError = error.userMessage
      return error
    }
  }

  /// "Restaurar disposição padrão" (`LayoutPanel.tsx:40-53`): forgets every
  /// saved grid layout. The answer carries the default, applied at once.
  @discardableResult
  public func resetGrid() async -> APIError? {
    isResettingGrid = true
    defer { isResettingGrid = false }
    resetError = nil
    do {
      let response = try await client.send(DashboardLayoutEndpoints.reset)
      dashboard.patch {
        $0.layout = response.layout
        $0.layouts = response.layouts
      }
      // The answer is the default (`resetDashboardLayout`).
      defaultLayout = response.layout
      return nil
    } catch {
      Logger.core.error("Grid layout reset failed: \(String(describing: error), privacy: .public)")
      resetError = Self.resetMessage
      return error
    }
  }

  // MARK: - Grade / Abas

  /// Switches the home between grid and tabs (`page.tsx:78-95`): the screen
  /// changes at once and goes back if the server refuses.
  @discardableResult
  public func setHomeView(_ view: HomeView) async -> APIError? {
    let previous = homeView
    guard view != previous else { return nil }
    viewError = nil
    dashboard.patch { $0.homeView = view }
    do {
      _ = try await client.send(DashboardLayoutEndpoints.homeView(view))
      return nil
    } catch {
      Logger.core.error("Home view update failed: \(String(describing: error), privacy: .public)")
      viewError = Self.text(for: error, fallback: Self.homeViewFallback)
      // A later switch owns the state now; going back would undo it.
      if dashboard.state?.homeView == view {
        dashboard.patch { $0.homeView = previous }
      }
      return error
    }
  }

  // MARK: - Abas, kept on this Mac

  /// The saved "Abas" document of `account`, or nil when there is none. The
  /// format belongs to `FeatureHome` (`WorkspaceLayout`); here it is opaque.
  public func loadWorkspace(account: LayoutAccount) throws -> Data? {
    guard let cache = cache(for: account) else { return memoryWorkspaces[account] }
    return try cache.load()
  }

  public func saveWorkspace(_ data: Data, account: LayoutAccount) throws {
    guard let cache = cache(for: account) else {
      memoryWorkspaces[account] = data
      return
    }
    try cache.save(data)
  }

  /// "Restaurar abas" (`page.tsx:97-100`): the next load finds nothing and
  /// falls back to the default.
  public func removeWorkspace(account: LayoutAccount) throws {
    guard let cache = cache(for: account) else {
      memoryWorkspaces[account] = nil
      return
    }
    try cache.remove()
  }

  private func cache(for account: LayoutAccount) -> DiskCache<Data>? {
    workspaceDirectory.map { DiskCache(fileName: account.fileName, directory: $0) }
  }

  /// The server's own text when it sent one, else the web's fallback for a
  /// body it could not read; connection failures keep their usual message.
  static func text(for error: APIError, fallback: String) -> String {
    switch error {
    case .server(_, let message, _, _) where !message.isEmpty: message
    case .server, .decoding, .invalidResponse: fallback
    default: error.userMessage
    }
  }
}
