import DailyModels

/// Calls shared by the shell and core (`docs/contracts/api.md`, "Sessão e conta" and "Estado").
public enum CoreEndpoints {
  /// `GET /api/me` (`app/api/me/route.ts`).
  public static var me: Endpoint<CurrentUser> { Endpoint(.get, "/api/me") }

  /// `GET /api/state`.
  public static var state: Endpoint<DashboardState> { Endpoint(.get, "/api/state") }

  /// `POST /api/refresh`: fetches every integration before answering.
  public static var refresh: Endpoint<DashboardState> { Endpoint(.post, "/api/refresh") }
}
