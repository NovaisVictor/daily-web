import DailyAPI
import DailyModels
import Foundation
import Observation
import os

/// Appearance, agenda window and tasks view (`PATCH /api/preferences`).
@Observable
public final class PreferencesStore {
  /// Prefix of the `UserDefaults` keys of the local appearance mirrors, one per
  /// account (server origin and username).
  public static let appearanceKey = "io.github.novaisvictor.dailyweb.appearance"
  /// `UserDefaults` key naming the mirror of the account signed in last, so the
  /// theme applies at launch before the session is checked.
  static let lastAccountKey = "io.github.novaisvictor.dailyweb.appearanceAccount"
  /// Values the server accepts for `agendaDays` (`lib/agendaWindow.ts`).
  public static let agendaRanges = [1, 2, 3, 7, 14]

  /// What the user chose.
  ///
  /// The server has no way to read it back: `app/api/preferences/route.ts`
  /// only has `PATCH`, and `/api/state` does not carry it. The local mirror is
  /// therefore the app's only source, kept per account and never wiped on
  /// sign-out. A change made on the web reaches the app only once the server
  /// offers a `GET` for it.
  public private(set) var appearance: Appearance
  public private(set) var isUpdatingAgendaDays = false

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let toasts: ToastCenter
  @ObservationIgnored private let defaults: UserDefaults
  /// The mirror key of the signed-in account; nil keeps changes in memory only.
  @ObservationIgnored private var account: String?
  /// Every appearance update and account switch takes a number; only the
  /// latest update's answer applies.
  @ObservationIgnored private var sequence = 0
  /// The update that last set each field, so a failure rolls back only the
  /// fields no later update touched.
  @ObservationIgnored private var owners: [AppearanceField: Int] = [:]

  public init(client: any APIClient, dashboard: DashboardStore, toasts: ToastCenter, defaults: UserDefaults) {
    self.client = client
    self.dashboard = dashboard
    self.toasts = toasts
    self.defaults = defaults
    let account = defaults.string(forKey: Self.lastAccountKey)
    self.account = account
    appearance = account.map { Self.loadMirror(defaults, key: $0) } ?? Appearance()
  }

  /// Switches to the mirror of the account that just signed in.
  public func activate(server: URL, username: String) {
    guard let origin = ServerOrigin(server) else {
      Logger.core.error("No appearance mirror for a server without an http(s) origin")
      deactivate()
      return
    }
    let key = "\(Self.appearanceKey).\(origin.description)|\(username)"
    sequence += 1
    owners = [:]
    account = key
    defaults.set(key, forKey: Self.lastAccountKey)
    appearance = Self.loadMirror(defaults, key: key)
  }

  /// Back to the defaults on sign-out. The account's mirror stays for its next sign-in.
  public func deactivate() {
    sequence += 1
    owners = [:]
    account = nil
    defaults.removeObject(forKey: Self.lastAccountKey)
    appearance = Appearance()
  }

  /// Saves the given fields (the others keep their value), applying them at once
  /// and going back if the server refuses.
  @discardableResult
  public func updateAppearance(_ patch: Appearance) async -> APIError? {
    sequence += 1
    let mine = sequence
    let before = appearance
    let fields = AppearanceField.allCases.filter { $0.isSet(in: patch) }
    for field in fields { owners[field] = mine }
    setAppearance(merged(before, patch))
    do {
      let response = try await client.send(PreferencesEndpoints.appearance(patch))
      guard mine == sequence else {
        // A later update, or another account, owns the appearance now; its own
        // answer carries the server's whole appearance.
        Logger.core.debug("Discarding a superseded appearance answer")
        return nil
      }
      owners = [:]
      setAppearance(response.appearance)
      return nil
    } catch {
      Logger.core.error("Appearance update failed: \(String(describing: error), privacy: .public)")
      var restored = appearance
      for field in fields where owners[field] == mine {
        field.copy(from: before, into: &restored)
        owners[field] = nil
      }
      if restored != appearance { setAppearance(restored) }
      toasts.error(error.userMessage)
      return error
    }
  }

  /// Changes how many days the agenda covers. The server refetches every
  /// integration and answers the whole state, so this is not optimistic.
  @discardableResult
  public func setAgendaDays(_ days: Int) async -> APIError? {
    guard Self.agendaRanges.contains(days) else {
      // Same text as the server's refusal (`route.ts:102`).
      let error = APIError.server(status: 400, message: "período inválido", code: nil, retry: nil)
      toasts.error(error.userMessage)
      return error
    }
    isUpdatingAgendaDays = true
    defer { isUpdatingAgendaDays = false }
    do {
      let state = try await client.send(PreferencesEndpoints.agendaDays(days))
      dashboard.apply(state)
      return nil
    } catch {
      Logger.core.error("Agenda range update failed: \(String(describing: error), privacy: .public)")
      toasts.error(error.userMessage)
      return error
    }
  }

  /// Switches the tasks panel between list and board, optimistically.
  @discardableResult
  public func setTasksView(_ view: TasksView) async -> APIError? {
    let client = self.client
    return await dashboard.mutate {
      $0.tasksView = view
    } commit: { () async throws(APIError) in
      _ = try await client.send(PreferencesEndpoints.tasksView(view))
    }
  }

  private func merged(_ base: Appearance, _ patch: Appearance) -> Appearance {
    Appearance(
      theme: patch.theme ?? base.theme,
      density: patch.density ?? base.density,
      backdrop: patch.backdrop ?? base.backdrop,
      width: patch.width ?? base.width
    )
  }

  private func setAppearance(_ value: Appearance) {
    appearance = value
    guard let account else { return }
    do {
      defaults.set(try JSONEncoder().encode(value), forKey: account)
    } catch {
      Logger.core.error("Could not mirror the appearance: \(String(describing: error), privacy: .public)")
    }
  }

  private static func loadMirror(_ defaults: UserDefaults, key: String) -> Appearance {
    guard let data = defaults.data(forKey: key) else { return Appearance() }
    do {
      return try JSONDecoder().decode(Appearance.self, from: data)
    } catch {
      Logger.core.error("Appearance mirror unreadable: \(String(describing: error), privacy: .public)")
      return Appearance()
    }
  }
}

private enum AppearanceField: CaseIterable {
  case theme, density, backdrop, width

  func isSet(in appearance: Appearance) -> Bool {
    switch self {
    case .theme: appearance.theme != nil
    case .density: appearance.density != nil
    case .backdrop: appearance.backdrop != nil
    case .width: appearance.width != nil
    }
  }

  func copy(from source: Appearance, into target: inout Appearance) {
    switch self {
    case .theme: target.theme = source.theme
    case .density: target.density = source.density
    case .backdrop: target.backdrop = source.backdrop
    case .width: target.width = source.width
    }
  }
}
