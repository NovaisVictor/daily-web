import DailyAPI
import DailyCore
import DailyModels

/// Marks dashboard notices read, for the bell and for the app's notification
/// actions ("Marcar como lida"), so the endpoint and the optimistic patch live
/// in one place.
public enum NotificationsReading {
  /// The badge drops at once; a refusal puts the notices back with a toast.
  /// One id goes as `{id}` and more as `{ids}` in pieces of 200, like the web
  /// (`app/api/notifications/read/route.ts`). When some pieces were saved before
  /// a failure, the server's state is read again: the rollback would show them unread.
  ///
  /// - Returns: The failure, already shown as a toast and logged by the dashboard.
  @discardableResult
  public static func markRead(ids: [String], environment: AppEnvironment) async -> APIError? {
    await markRead(ids: ids, client: environment.client, dashboard: environment.dashboard)
  }

  /// - Parameter alwaysAsList: Sends `{ids}` even for one notice, the shape of
  ///   the web's "Marcar todas como lidas" (`markAllRead`).
  @discardableResult
  static func markRead(
    ids: [String], client: any APIClient, dashboard: DashboardStore, alwaysAsList: Bool = false
  ) async -> APIError? {
    guard !ids.isEmpty else { return nil }
    var delivered = 0
    let failure = await dashboard.mutate { state in
      NotificationsLogic.markRead(ids, in: &state)
    } commit: { () async throws(APIError) in
      if ids.count == 1, !alwaysAsList {
        _ = try await client.send(NotificationsEndpoints.markRead(id: ids[0]))
        return
      }
      for chunk in NotificationsLogic.chunks(ids) {
        _ = try await client.send(NotificationsEndpoints.markRead(ids: chunk))
        delivered += 1
      }
    }
    if failure != nil, delivered > 0 { await dashboard.reload() }
    return failure
  }
}
