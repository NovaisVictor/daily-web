// FROZEN NAME (T006): owned by T101 from here on; fields may be added, not renamed.

/// The signed-in account, as `GET /api/me` returns it (`app/api/me/route.ts:9-15`).
public struct CurrentUser: Codable, Sendable, Equatable {
  public var username: String
  public var isAdmin: Bool
  public var avatarUrl: String?
  public var fullName: String?
  public var email: String?

  public init(username: String, isAdmin: Bool, avatarUrl: String?, fullName: String?, email: String?) {
    self.username = username
    self.isAdmin = isAdmin
    self.avatarUrl = avatarUrl
    self.fullName = fullName
    self.email = email
  }
}
