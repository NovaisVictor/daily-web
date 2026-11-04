import DailyAPI
import DailyModels
import Foundation
import Observation
import os

/// Appearance, agenda window and tasks view (`PATCH /api/preferences`).
@Observable
public final class PreferencesStore {
  /// `UserDefaults` key of the local appearance mirror.
  public static let appearanceKey = "io.github.novaisvictor.dailyweb.appearance"
  /// Values the server accepts for `agendaDays` (`lib/agendaWindow.ts`).
  public static let agendaRanges = [1, 2, 3, 7, 14]

  /// What the user chose. Mirrored on disk so the theme applies before the
  /// first network answer.
  public private(set) var appearance: Appearance
  public private(set) var isUpdatingAgendaDays = false

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let dashboard: DashboardStore
  @ObservationIgnored private let toasts: ToastCenter
  @ObservationIgnored private let defaults: UserDefaults

  public init(client: any APIClient, dashboard: DashboardStore, toasts: ToastCenter, defaults: UserDefaults) {
    self.client = client
    self.dashboard = dashboard
    self.toasts = toasts
    self.defaults = defaults
    appearance = Self.loadMirror(defaults)
  }

  /// Saves the given fields (the others keep their value), applying them at once
  /// and going back if the server refuses.
  @discardableResult
  public func updateAppearance(_ patch: Appearance) async -> APIError? {
    let before = appearance
    setAppearance(merged(before, patch))
    do {
      let response = try await client.send(PreferencesEndpoints.appearance(patch))
      setAppearance(response.appearance)
      return nil
    } catch {
      Logger.core.error("Appearance update failed: \(String(describing: error), privacy: .public)")
      setAppearance(before)
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

  /// Forgets the mirror on sign-out, so the next account starts from the defaults.
  public func clear() {
    defaults.removeObject(forKey: Self.appearanceKey)
    appearance = Appearance()
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
    do {
      defaults.set(try JSONEncoder().encode(value), forKey: Self.appearanceKey)
    } catch {
      Logger.core.error("Could not mirror the appearance: \(String(describing: error), privacy: .public)")
    }
  }

  private static func loadMirror(_ defaults: UserDefaults) -> Appearance {
    guard let data = defaults.data(forKey: appearanceKey) else { return Appearance() }
    do {
      return try JSONDecoder().decode(Appearance.self, from: data)
    } catch {
      Logger.core.error("Appearance mirror unreadable: \(String(describing: error), privacy: .public)")
      return Appearance()
    }
  }
}
