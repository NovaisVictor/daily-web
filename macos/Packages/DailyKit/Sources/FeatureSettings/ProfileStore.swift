import DailyAPI
import DailyModels
import Foundation
import Observation
import UniformTypeIdentifiers
import os

/// Turns a picked image into the `data:` URL `POST /api/me/avatar` takes,
/// refusing what the server would (`app/api/me/avatar/route.ts`).
enum AvatarEncoder {
  /// 2 MB, `MAX_BYTES`.
  static let maxBytes = 2 * 1024 * 1024
  static let allowedTypes: [UTType] = [.png, .jpeg, .webP, .gif]

  struct Refusal: Error, Equatable {
    let message: String
  }

  static func mimeType(for type: UTType) -> String? {
    if type.conforms(to: .png) { return "image/png" }
    if type.conforms(to: .jpeg) { return "image/jpeg" }
    if type.conforms(to: .webP) { return "image/webp" }
    if type.conforms(to: .gif) { return "image/gif" }
    return nil
  }

  /// The server's own texts. The size is estimated from the base64 length,
  /// like the server, so both sides draw the line at the same place.
  static func dataURL(for data: Data, type: UTType) -> Result<String, Refusal> {
    guard let mime = mimeType(for: type) else {
      return .failure(Refusal(message: "formato de imagem não suportado"))
    }
    let base64 = data.base64EncodedString()
    guard !base64.isEmpty else { return .failure(Refusal(message: "imagem inválida")) }
    guard base64.count * 3 / 4 <= maxBytes else { return .failure(Refusal(message: "imagem maior que 2MB")) }
    return .success("data:\(mime);base64,\(base64)")
  }

  /// The image bytes of a `data:` URL, for the avatar view.
  static func imageData(fromDataURL url: String?) -> Data? {
    guard let url, url.hasPrefix("data:"), let comma = url.firstIndex(of: ",") else { return nil }
    return Data(base64Encoded: String(url[url.index(after: comma)...]))
  }
}

/// The profile tab (`components/ProfilePanel.tsx`).
@Observable
final class ProfileStore {
  private(set) var me: CurrentUser?
  private(set) var isLoading = false
  private(set) var loadError: String?

  var fullName = ""
  var email = ""
  private(set) var isSavingProfile = false
  private(set) var profileError: String?

  private(set) var isUploadingAvatar = false
  private(set) var avatarError: String?

  var currentPassword = ""
  var newPassword = ""
  var confirmPassword = ""
  private(set) var isChangingPassword = false
  private(set) var passwordError: String?
  private(set) var passwordSaved = false

  @ObservationIgnored private let client: any APIClient
  /// Tells the session about the new profile, so the shell shows it.
  @ObservationIgnored private let onUserChanged: (CurrentUser) -> Void

  init(client: any APIClient, user: CurrentUser?, onUserChanged: @escaping (CurrentUser) -> Void = { _ in }) {
    self.client = client
    self.onUserChanged = onUserChanged
    if let user { fill(user) }
  }

  var canChangePassword: Bool {
    !isChangingPassword && !currentPassword.isEmpty && !newPassword.isEmpty
  }

  func load() async {
    isLoading = me == nil
    defer { isLoading = false }
    do {
      let user = try await client.send(ProfileEndpoints.me)
      fill(user)
      loadError = nil
    } catch {
      Logger.settings.error("Profile load failed: \(String(describing: error), privacy: .public)")
      if me == nil { loadError = error.userMessage }
    }
  }

  /// `PATCH /api/me` with both fields: an absent key would clear it.
  func saveProfile() async {
    isSavingProfile = true
    defer { isSavingProfile = false }
    profileError = nil
    do {
      let saved = try await client.send(ProfileEndpoints.update(fullName: fullName, email: email))
      guard var user = me else { return }
      user.fullName = saved.fullName
      user.email = saved.email
      me = user
      onUserChanged(user)
    } catch {
      Logger.settings.error("Profile save failed: \(String(describing: error), privacy: .public)")
      profileError = error.userMessage
    }
  }

  /// Reads the picked file, checks it like the server and uploads it.
  func uploadAvatar(from url: URL) async {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    let data: Data
    let type: UTType?
    do {
      data = try Data(contentsOf: url)
      type =
        try url.resourceValues(forKeys: [.contentTypeKey]).contentType ?? UTType(filenameExtension: url.pathExtension)
    } catch {
      Logger.settings.error("Could not read the picked photo: \(String(describing: error), privacy: .public)")
      avatarError = "Falha ao enviar a foto"
      return
    }
    guard let type else {
      avatarError = "formato de imagem não suportado"
      return
    }
    await uploadAvatar(data: data, type: type)
  }

  func uploadAvatar(data: Data, type: UTType) async {
    avatarError = nil
    let dataURL: String
    switch AvatarEncoder.dataURL(for: data, type: type) {
    case .success(let value): dataURL = value
    case .failure(let refusal):
      avatarError = refusal.message
      return
    }
    isUploadingAvatar = true
    defer { isUploadingAvatar = false }
    do {
      let response = try await client.send(ProfileEndpoints.uploadAvatar(dataURL: dataURL))
      setAvatar(response.avatarUrl)
    } catch {
      Logger.settings.error("Avatar upload failed: \(String(describing: error), privacy: .public)")
      avatarError = error.userMessage
    }
  }

  func removeAvatar() async {
    isUploadingAvatar = true
    defer { isUploadingAvatar = false }
    avatarError = nil
    do {
      let response = try await client.send(ProfileEndpoints.removeAvatar)
      setAvatar(response.avatarUrl)
    } catch {
      Logger.settings.error("Avatar removal failed: \(String(describing: error), privacy: .public)")
      avatarError = error.userMessage
    }
  }

  /// `POST /api/me/password`, after checking the confirmation locally.
  func changePassword() async {
    passwordError = nil
    passwordSaved = false
    guard newPassword == confirmPassword else {
      passwordError = "as senhas novas não coincidem"
      return
    }
    isChangingPassword = true
    defer { isChangingPassword = false }
    do {
      _ = try await client.send(ProfileEndpoints.changePassword(current: currentPassword, new: newPassword))
      currentPassword = ""
      newPassword = ""
      confirmPassword = ""
      passwordSaved = true
    } catch {
      Logger.settings.error("Password change failed: \(String(describing: error), privacy: .public)")
      passwordError = error.userMessage
    }
  }

  private func fill(_ user: CurrentUser) {
    me = user
    fullName = user.fullName ?? ""
    email = user.email ?? ""
  }

  private func setAvatar(_ url: String?) {
    guard var user = me else { return }
    user.avatarUrl = url
    me = user
    onUserChanged(user)
  }
}
