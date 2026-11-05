import DailyAPI
import DailyModels
import Foundation
import os

nonisolated extension Logger {
  static let settings = Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureSettings")
}

/// `app/api/integrations/**` (`docs/contracts/api.md`, "Integrações").
nonisolated enum IntegrationsEndpoints {
  /// Both keys always go: the server keeps the old label only for a blank one.
  struct ConnectionBody: Encodable, Sendable, Equatable {
    let label: String
    let values: [String: String]
  }

  struct TestBody: Encodable, Sendable, Equatable {
    let id: String
  }

  struct CalendarsBody: Encodable, Sendable, Equatable {
    let id: String
    let calendarIds: [String]
  }

  static var list: Endpoint<IntegrationsPayload> { Endpoint(.get, "/api/integrations") }

  static func create(_ module: ModuleID, _ body: ConnectionBody) -> Endpoint<ModulesResponse> {
    Endpoint(.post, "/api/integrations/\(Endpoint<ModulesResponse>.segment(module.rawValue))/connections", body: body)
  }

  static func update(_ module: ModuleID, id: String, _ body: ConnectionBody) -> Endpoint<ModulesResponse> {
    Endpoint(.put, connectionPath(module, id), body: body)
  }

  static func remove(_ module: ModuleID, id: String) -> Endpoint<ConnectionRemovedResponse> {
    Endpoint(.delete, connectionPath(module, id))
  }

  /// Always 200: a failed check is a result, not an error (`…/test/route.ts`).
  static func test(_ module: ModuleID, id: String) -> Endpoint<ConnectionTestResult> {
    Endpoint(
      .post, "/api/integrations/\(Endpoint<ConnectionTestResult>.segment(module.rawValue))/test",
      body: TestBody(id: id))
  }

  static func calendars(connection id: String) -> Endpoint<GoogleCalendarsResponse> {
    Endpoint(.get, "/api/integrations/agenda/google/calendars", query: [URLQueryItem(name: "id", value: id)])
  }

  static func saveCalendars(connection id: String, calendarIds: [String]) -> Endpoint<ModulesResponse> {
    Endpoint(.patch, "/api/integrations/agenda/google/calendars", body: CalendarsBody(id: id, calendarIds: calendarIds))
  }

  private static func connectionPath(_ module: ModuleID, _ id: String) -> String {
    "/api/integrations/\(Endpoint<EmptyResponse>.segment(module.rawValue))/connections/"
      + Endpoint<EmptyResponse>.segment(id)
  }
}

/// `app/api/me/**` (`docs/contracts/api.md`, "Sessão e conta").
nonisolated enum ProfileEndpoints {
  /// Non-optional on purpose: a missing key clears that field on the server
  /// (`app/api/me/route.ts:27-28`), so both always go.
  struct ProfileBody: Encodable, Sendable, Equatable {
    let fullName: String
    let email: String
  }

  struct PasswordBody: Encodable, Sendable, Equatable {
    let currentPassword: String
    let newPassword: String
  }

  struct AvatarBody: Encodable, Sendable, Equatable {
    let dataUrl: String
  }

  static var me: Endpoint<CurrentUser> { CoreEndpoints.me }

  static func update(fullName: String, email: String) -> Endpoint<ProfileResponse> {
    Endpoint(.patch, "/api/me", body: ProfileBody(fullName: fullName, email: email))
  }

  static func changePassword(current: String, new: String) -> Endpoint<EmptyResponse> {
    Endpoint(
      .post, "/api/me/password", body: PasswordBody(currentPassword: current, newPassword: new),
      checksCredentials: true)
  }

  static func uploadAvatar(dataURL: String) -> Endpoint<AvatarResponse> {
    Endpoint(.post, "/api/me/avatar", body: AvatarBody(dataUrl: dataURL))
  }

  static var removeAvatar: Endpoint<AvatarResponse> { Endpoint(.delete, "/api/me/avatar") }
}

/// `app/api/users/**`, admin only except a password change of one's own.
nonisolated enum UsersEndpoints {
  struct CreateBody: Encodable, Sendable, Equatable {
    let username: String
    let password: String
    let isAdmin: Bool
  }

  struct PasswordBody: Encodable, Sendable, Equatable {
    let password: String
  }

  static var list: Endpoint<UsersResponse> { Endpoint(.get, "/api/users") }

  static func create(username: String, password: String, isAdmin: Bool) -> Endpoint<CreatedUserResponse> {
    Endpoint(.post, "/api/users", body: CreateBody(username: username, password: password, isAdmin: isAdmin))
  }

  static func setPassword(_ username: String, password: String) -> Endpoint<EmptyResponse> {
    Endpoint(.patch, "/api/users/\(Endpoint<EmptyResponse>.segment(username))", body: PasswordBody(password: password))
  }

  static func remove(_ username: String) -> Endpoint<EmptyResponse> {
    Endpoint(.delete, "/api/users/\(Endpoint<EmptyResponse>.segment(username))")
  }
}

/// The panel layout of the Home grid (`app/api/preferences/**`, spec 010 FR-010-11).
nonisolated enum LayoutEndpoints {
  /// `{layout: null}`: the synthesized encoder would drop a nil key, and the
  /// server only resets when the key is present and null (`route.ts:60-62`).
  struct ResetBody: Encodable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey { case layout }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeNil(forKey: .layout)
    }
  }

  /// `app/api/preferences/layout-default/route.ts`.
  static var layoutDefault: Endpoint<LayoutDefaultResponse> { Endpoint(.get, "/api/preferences/layout-default") }

  static var reset: Endpoint<LayoutResponse> { Endpoint(.patch, "/api/preferences", body: ResetBody()) }
}

/// `GET /api/preferences/layout-default`.
nonisolated struct LayoutDefaultResponse: Codable, Sendable, Equatable {
  let layout: [LayoutItem]
}
