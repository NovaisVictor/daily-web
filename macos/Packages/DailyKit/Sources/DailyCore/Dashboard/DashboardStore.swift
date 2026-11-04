import DailyAPI
import DailyModels
import DailyStorage
import Foundation
import Observation
import os

/// One change to `DashboardStore.state`, for the stores that follow it.
public struct DashboardChange {
  public enum Origin: Sendable, Equatable {
    /// Read from the disk cache at launch.
    case cache
    /// A full state from the server (poll, manual refresh, `apply`).
    case server
    /// A local edit: optimistic mutation, rollback or `patch`.
    case local
  }

  public let previous: DashboardState?
  public let current: DashboardState
  public let origin: Origin
}

/// The shared dashboard state, one for the whole app, like the web's
/// `DashboardStateProvider` (`lib/hooks/DashboardStateProvider.tsx`).
@Observable
public final class DashboardStore {
  public private(set) var state: DashboardState?
  /// The last failed read; cleared by the next good one.
  public private(set) var lastError: APIError?
  public private(set) var isRefreshing = false
  /// When the server last answered with a full state.
  public private(set) var lastUpdated: Date?

  @ObservationIgnored private let client: any APIClient
  @ObservationIgnored private let cache: DiskCache<DashboardState>?
  @ObservationIgnored private let toasts: ToastCenter
  @ObservationIgnored private let now: Now
  /// Same idea as `geracao` in `lib/hooks/usePolling.tsx:15`: every read and
  /// every local change takes a number, and a read may only write the state if
  /// nothing happened since it started.
  @ObservationIgnored private var generation = 0
  /// Mutations whose commit has not answered yet; no read applies meanwhile.
  @ObservationIgnored private var pendingMutations = 0
  @ObservationIgnored private var listeners: [(DashboardChange) -> Void] = []

  public init(
    client: any APIClient,
    cache: DiskCache<DashboardState>?,
    toasts: ToastCenter,
    now: @escaping Now = LiveTime.now
  ) {
    self.client = client
    self.cache = cache
    self.toasts = toasts
    self.now = now
  }

  /// Calls `listener` after every change, in registration order.
  public func observe(_ listener: @escaping (DashboardChange) -> Void) {
    listeners.append(listener)
  }

  // MARK: - Reading

  /// Shows the last saved state, if any, so the window opens filled.
  public func loadCached() {
    guard state == nil, let cache else { return }
    let cached: DashboardState?
    do {
      cached = try cache.load()
    } catch {
      Logger.core.error("Dashboard cache unreadable: \(String(describing: error), privacy: .public)")
      return
    }
    guard let cached else { return }
    set(cached, origin: .cache)
  }

  /// The cache first, then `GET /api/state`.
  public func start() async {
    loadCached()
    await reload()
  }

  /// `GET /api/state`, the poll.
  public func reload() async {
    await read(CoreEndpoints.state, label: "state")
  }

  /// `POST /api/refresh`, the manual refresh (⌘R): fetches every integration first.
  public func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    if let error = await read(CoreEndpoints.refresh, label: "refresh") {
      // The web stays silent (`usePolling.tsx:33`); here the person pressed a
      // button and waits for an answer, so the failure is shown.
      toasts.error(error.userMessage)
    }
  }

  @discardableResult
  private func read(_ endpoint: Endpoint<DashboardState>, label: String) async -> APIError? {
    generation += 1
    let mine = generation
    do {
      let fresh = try await client.send(endpoint)
      guard mine == generation, pendingMutations == 0 else {
        Logger.core.debug("Discarding a stale \(label, privacy: .public) answer")
        return nil
      }
      lastError = nil
      lastUpdated = now()
      set(fresh, origin: .server)
      return nil
    } catch {
      if case .cancelled = error { return nil }
      Logger.core.error("Dashboard \(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      lastError = error
      return error
    }
  }

  // MARK: - Writing

  /// Applies `change` at once, then runs `commit`. On failure the state goes back
  /// to what it was and an error toast shows (`usePolling.tsx:40-53`).
  ///
  /// Reads in flight when the mutation starts, or started while `commit` runs,
  /// carry the state from before the change and are discarded.
  @discardableResult
  public func mutate(
    _ change: (inout DashboardState) -> Void,
    commit: () async throws(APIError) -> Void
  ) async -> APIError? {
    generation += 1
    pendingMutations += 1
    defer { pendingMutations -= 1 }
    let before = state
    var optimistic: DashboardState?
    if var next = state {
      change(&next)
      optimistic = next
      set(next, origin: .local)
    }
    do {
      try await commit()
      generation += 1
      return nil
    } catch {
      generation += 1
      Logger.core.error("Mutation failed: \(String(describing: error), privacy: .public)")
      if let before, state == optimistic {
        set(before, origin: .local)
      } else if before != nil {
        // Something else changed the state meanwhile; restoring the snapshot
        // would undo that too, so the server decides.
        Task { await self.reload() }
      }
      toasts.error(error.userMessage)
      return error
    }
  }

  /// Replaces the state with a full one the server returned from a write
  /// (`PATCH /api/preferences` with `agendaDays`, Jira watch).
  public func apply(_ fresh: DashboardState) {
    generation += 1
    lastUpdated = now()
    lastError = nil
    set(fresh, origin: .server)
  }

  /// A change the server already confirmed, such as a pomodoro answer or a new
  /// agenda item. Invalidates reads in flight like `mutate`.
  public func patch(_ change: (inout DashboardState) -> Void) {
    guard var next = state else { return }
    generation += 1
    change(&next)
    set(next, origin: .local)
  }

  /// Forgets everything, on sign-out: memory and the cache file.
  public func clear() {
    generation += 1
    state = nil
    lastError = nil
    lastUpdated = nil
    isRefreshing = false
    guard let cache else { return }
    do {
      try cache.remove()
    } catch {
      Logger.core.error("Could not delete the dashboard cache: \(String(describing: error), privacy: .public)")
    }
  }

  private func set(_ next: DashboardState, origin: DashboardChange.Origin) {
    let previous = state
    state = next
    if origin != .cache { save(next) }
    let change = DashboardChange(previous: previous, current: next, origin: origin)
    for listener in listeners { listener(change) }
  }

  private func save(_ value: DashboardState) {
    guard let cache else { return }
    do {
      try cache.save(value)
    } catch {
      // The cache only speeds up the next launch; the app works without it.
      Logger.core.error("Could not save the dashboard cache: \(String(describing: error), privacy: .public)")
    }
  }
}
