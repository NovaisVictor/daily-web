/// `PATCH /api/me` (`app/api/me/route.ts:27-34`): the saved profile, where an
/// empty value comes back as null.
public struct ProfileResponse: Codable, Sendable, Equatable, Hashable {
  public var fullName: String?
  public var email: String?

  public init(fullName: String?, email: String?) {
    self.fullName = fullName
    self.email = email
  }
}

/// `POST` and `DELETE /api/me/avatar` (`app/api/me/avatar/route.ts:32,40`).
/// The url is a `data:` url, or null once removed.
public struct AvatarResponse: Codable, Sendable, Equatable, Hashable {
  public var avatarUrl: String?

  public init(avatarUrl: String?) {
    self.avatarUrl = avatarUrl
  }
}

/// One account as the admin list shows it, never with the password hash
/// (`app/api/users/route.ts:7-9`).
public struct UserSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var username: String
  public var isAdmin: Bool
  public var createdAt: String

  public init(id: String, username: String, isAdmin: Bool, createdAt: String) {
    self.id = id
    self.username = username
    self.isAdmin = isAdmin
    self.createdAt = createdAt
  }
}

/// `GET /api/users` (`app/api/users/route.ts:15`).
public struct UsersResponse: Codable, Sendable, Equatable, Hashable {
  public var users: [UserSummary]

  public init(users: [UserSummary]) {
    self.users = users
  }
}

/// `POST /api/users`, status 201 (`app/api/users/route.ts:30`).
public struct CreatedUserResponse: Codable, Sendable, Equatable, Hashable {
  public var user: UserSummary

  public init(user: UserSummary) {
    self.user = user
  }
}
