import DailyAPI
import DailyModels
import Foundation
import Observation
import os

/// The users tab, admin only (`components/UsersPanel.tsx`).
@Observable
final class UsersStore {
  private(set) var users: [UserSummary] = []
  private(set) var isLoading = false
  private(set) var error: String?
  /// The server answered 403: only admins manage users.
  private(set) var forbidden = false

  var username = ""
  var password = ""
  var isAdmin = false
  private(set) var isCreating = false

  /// The user whose inline password form is open.
  private(set) var resetFor: String?
  var resetPassword = ""

  @ObservationIgnored private let client: any APIClient

  init(client: any APIClient) {
    self.client = client
  }

  var canCreate: Bool {
    !isCreating && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
  }

  func load() async {
    isLoading = users.isEmpty
    defer { isLoading = false }
    do {
      users = try await client.send(UsersEndpoints.list).users
      error = nil
    } catch .server(status: 403, _, _, _) {
      forbidden = true
    } catch {
      Logger.settings.error("Users load failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }

  func create() async {
    isCreating = true
    defer { isCreating = false }
    do {
      _ = try await client.send(UsersEndpoints.create(username: username, password: password, isAdmin: isAdmin))
      error = nil
      username = ""
      password = ""
      isAdmin = false
      await load()
    } catch {
      Logger.settings.error("User creation failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }

  /// Called after the confirmation.
  func remove(_ user: UserSummary) async {
    do {
      _ = try await client.send(UsersEndpoints.remove(user.username))
      error = nil
      await load()
    } catch {
      Logger.settings.error("User removal failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }

  func toggleReset(_ username: String) {
    resetFor = resetFor == username ? nil : username
    resetPassword = ""
  }

  func changePassword(_ username: String) async {
    do {
      _ = try await client.send(UsersEndpoints.setPassword(username, password: resetPassword))
      error = nil
      resetFor = nil
      resetPassword = ""
    } catch {
      Logger.settings.error("User password change failed: \(String(describing: error), privacy: .public)")
      self.error = error.userMessage
    }
  }
}
