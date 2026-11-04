import DailyAPI
import DailyModels
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import FeatureSettings

@MainActor
final class UserRecorder {
  var users: [CurrentUser] = []
}

@Suite struct AvatarEncoderTests {
  @Test(arguments: [
    (UTType.png, "image/png"), (.jpeg, "image/jpeg"), (.webP, "image/webp"), (.gif, "image/gif"),
  ])
  func encodesTheAcceptedTypes(type: UTType, mime: String) {
    #expect(AvatarEncoder.dataURL(for: Data([1, 2, 3]), type: type) == .success("data:\(mime);base64,AQID"))
  }

  @Test func refusesOtherTypes() {
    #expect(
      AvatarEncoder.dataURL(for: Data([1]), type: .pdf)
        == .failure(AvatarEncoder.Refusal(message: "formato de imagem não suportado")))
    #expect(
      AvatarEncoder.dataURL(for: Data([1]), type: .heic)
        == .failure(AvatarEncoder.Refusal(message: "formato de imagem não suportado")))
  }

  // The server measures the base64 length (padding included), so a file of
  // exactly 2 MB is already over; 2 MB minus 2 bytes is the largest accepted.
  @Test func drawsTheSizeLineWhereTheServerDoes() throws {
    let largest = try AvatarEncoder.dataURL(for: Data(count: AvatarEncoder.maxBytes - 2), type: .png).get()
    #expect(largest.hasPrefix("data:image/png;base64,"))
    #expect(
      AvatarEncoder.dataURL(for: Data(count: AvatarEncoder.maxBytes), type: .png)
        == .failure(AvatarEncoder.Refusal(message: "imagem maior que 2MB")))
  }

  @Test func readsTheImageBackFromTheDataURL() {
    #expect(AvatarEncoder.imageData(fromDataURL: "data:image/png;base64,AQID") == Data([1, 2, 3]))
    #expect(AvatarEncoder.imageData(fromDataURL: nil) == nil)
    #expect(AvatarEncoder.imageData(fromDataURL: "https://example.com/a.png") == nil)
  }
}

@Suite struct ProfileStoreTests {
  let client = RecordingAPIClient()
  let recorder = UserRecorder()
  let store: ProfileStore
  let user = CurrentUser(
    username: "ana", isAdmin: true, avatarUrl: nil, fullName: "Ana Souza", email: "ana@example.com")

  init() {
    let recorder = self.recorder
    store = ProfileStore(client: client, user: user) { recorder.users.append($0) }
  }

  @Test func loadsTheProfile() async {
    let fresh = CurrentUser(username: "ana", isAdmin: true, avatarUrl: nil, fullName: "Ana S.", email: nil)
    client.respond { _ in RecordingAPIClient.json(fresh) }
    await store.load()
    #expect(client.calls.map { "\($0.method) \($0.path)" } == ["GET /api/me"])
    #expect(store.fullName == "Ana S.")
    #expect(store.email == "")
  }

  // A missing key clears that field on the server, so both always go.
  @Test func savesBothFieldsEvenWhenEmpty() async throws {
    store.fullName = ""
    client.respond { _ in Data(#"{"fullName":null,"email":"ana@example.com"}"#.utf8) }

    await store.saveProfile()

    let call = try #require(client.calls.last)
    #expect("\(call.method) \(call.path)" == "PATCH /api/me")
    #expect(call.body == #"{"email":"ana@example.com","fullName":""}"#)
    #expect(store.me?.fullName == nil)
    #expect(recorder.users.last?.fullName == nil)
    #expect(recorder.users.last?.email == "ana@example.com")
  }

  @Test func showsTheServerRefusal() async {
    client.respond { _ throws(APIError) in throw .server(status: 400, message: "e-mail inválido", code: nil, retry: nil)
    }
    await store.saveProfile()
    #expect(store.profileError == "e-mail inválido")
    #expect(recorder.users.isEmpty)
  }

  @Test func refusesAMismatchedConfirmation() async {
    store.currentPassword = "antiga-123"
    store.newPassword = "nova-senha-1"
    store.confirmPassword = "nova-senha-2"
    await store.changePassword()
    #expect(store.passwordError == "as senhas novas não coincidem")
    #expect(client.calls.isEmpty)
  }

  @Test func changesThePassword() async throws {
    store.currentPassword = "antiga-123"
    store.newPassword = "nova-senha-1"
    store.confirmPassword = "nova-senha-1"

    await store.changePassword()

    let call = try #require(client.calls.last)
    #expect("\(call.method) \(call.path)" == "POST /api/me/password")
    #expect(call.body == #"{"currentPassword":"antiga-123","newPassword":"nova-senha-1"}"#)
    #expect(store.passwordSaved)
    #expect(store.currentPassword.isEmpty && store.newPassword.isEmpty && store.confirmPassword.isEmpty)
  }

  @Test func uploadsAndRemovesThePhoto() async throws {
    client.respond { _ in Data(#"{"avatarUrl":"data:image/png;base64,AQID"}"#.utf8) }
    await store.uploadAvatar(data: Data([1, 2, 3]), type: .png)

    let upload = try #require(client.calls.last)
    #expect("\(upload.method) \(upload.path)" == "POST /api/me/avatar")
    #expect(upload.body == #"{"dataUrl":"data:image/png;base64,AQID"}"#)
    #expect(store.me?.avatarUrl == "data:image/png;base64,AQID")
    #expect(recorder.users.last?.avatarUrl == "data:image/png;base64,AQID")

    client.respond { _ in Data(#"{"avatarUrl":null}"#.utf8) }
    await store.removeAvatar()
    #expect(client.calls.last.map { "\($0.method) \($0.path)" } == "DELETE /api/me/avatar")
    #expect(store.me?.avatarUrl == nil)
  }

  @Test func aRefusedPhotoNeverLeaves() async {
    await store.uploadAvatar(data: Data(count: AvatarEncoder.maxBytes + 3), type: .png)
    #expect(store.avatarError == "imagem maior que 2MB")
    #expect(client.calls.isEmpty)
  }
}

@Suite struct UsersStoreTests {
  let client = RecordingAPIClient()
  let store: UsersStore
  let list = Data(
    #"{"users":[{"id":"1","username":"ana","isAdmin":true,"createdAt":"2026-10-01T10:00:00.000Z"}]}"#.utf8)

  init() {
    store = UsersStore(client: client)
  }

  @Test func listsTheUsers() async {
    let list = self.list
    client.respond { _ in list }
    await store.load()
    #expect(client.calls.map { "\($0.method) \($0.path)" } == ["GET /api/users"])
    #expect(store.users.map(\.username) == ["ana"])
  }

  @Test func aNonAdminSeesTheWebMessage() async {
    client.respond { _ throws(APIError) in throw .server(status: 403, message: "apenas admin", code: nil, retry: nil) }
    await store.load()
    #expect(store.forbidden)
    #expect(store.error == nil)
  }

  @Test func createsAUserAndReloads() async {
    let list = self.list
    client.respond { call in
      call.method == "POST"
        ? Data(#"{"user":{"id":"2","username":"bruno","isAdmin":false,"createdAt":""}}"#.utf8) : list
    }
    store.username = "bruno"
    store.password = "senha-longa"
    store.isAdmin = true

    await store.create()

    #expect(client.calls.map { "\($0.method) \($0.path)" } == ["POST /api/users", "GET /api/users"])
    #expect(client.calls.first?.body == #"{"isAdmin":true,"password":"senha-longa","username":"bruno"}"#)
    #expect(store.username.isEmpty && store.password.isEmpty && !store.isAdmin)
  }

  @Test func keepsTheFormWhenCreationFails() async {
    client.respond { _ throws(APIError) in
      throw .server(status: 400, message: "usuário já existe", code: nil, retry: nil)
    }
    store.username = "ana"
    store.password = "senha-longa"
    await store.create()
    #expect(store.error == "usuário já existe")
    #expect(store.username == "ana")
  }

  @Test func changesAndRemovesAUser() async {
    store.toggleReset("bruno silva")
    store.resetPassword = "outra-senha"
    await store.changePassword("bruno silva")
    #expect(client.calls.first.map { "\($0.method) \($0.path)" } == "PATCH /api/users/bruno%20silva")
    #expect(client.calls.first?.body == #"{"password":"outra-senha"}"#)
    #expect(store.resetFor == nil)

    let list = self.list
    client.respond { call in call.method == "DELETE" ? RecordingAPIClient.ok : list }
    await store.remove(UserSummary(id: "2", username: "bruno silva", isAdmin: false, createdAt: ""))
    #expect(
      client.calls.dropFirst().map { "\($0.method) \($0.path)" } == [
        "DELETE /api/users/bruno%20silva", "GET /api/users",
      ])
  }

  @Test func createNeedsANameAndAPassword() {
    store.username = "  "
    store.password = "x"
    #expect(!store.canCreate)
    store.username = "ana"
    #expect(store.canCreate)
  }
}
