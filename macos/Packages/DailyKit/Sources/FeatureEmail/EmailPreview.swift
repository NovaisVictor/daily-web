import DailyCore
import DailyModels
import Foundation
import os

/// Sample answers for the previews: made-up messages, no network.
enum EmailPreview {
  static func store() -> EmailStore {
    let client = PreviewAPIClient(responses: responses)
    let environment = AppEnvironment(
      rawClient: client,
      tokenStore: InMemorySessionStorage(),
      settings: InMemorySessionStorage(),
      cacheDirectory: nil,
      defaults: UserDefaults(suiteName: "io.github.novaisvictor.dailyweb.preview.email") ?? .standard,
      poster: SilentNotificationPoster()
    )
    environment.dashboard.apply(PreviewFixtures.dashboard)
    return EmailStore(
      client: environment.client, dashboard: environment.dashboard, navigator: environment.navigator)
  }

  private static var responses: [String: Data] {
    let encoder = JSONEncoder()
    var responses: [String: Data] = [:]
    do {
      let mailboxes = MailboxesResponse(
        mailboxes: [
          MailboxNode(
            path: "INBOX", name: "Inbox", delimiter: "/", parent: nil, specialUse: nil, total: 2, unread: 1),
          MailboxNode(
            path: "Clientes", name: "Clientes", delimiter: "/", parent: nil, specialUse: nil, total: 4, unread: 0),
          MailboxNode(
            path: "Clientes/Acme", name: "Acme", delimiter: "/", parent: "Clientes", specialUse: nil, total: 3,
            unread: 2),
          MailboxNode(
            path: "Sent", name: "Enviados", delimiter: "/", parent: nil, specialUse: "\\Sent", total: 9, unread: 0),
        ],
        syncedAt: "2026-11-04T12:00:00.000Z", cached: true)
      responses["GET /api/email/mailboxes"] = try encoder.encode(mailboxes)
      responses["GET /api/email/folders"] = try encoder.encode(
        EmailFoldersResponse(folders: ["Clientes", "Clientes/Acme", "Arquivo"]))
      responses["GET /api/email/conn-mail-1/4182/body"] = try encoder.encode(
        EmailBody(
          text: "Oi Ana,\n\nSegue o relatório: https://example.com/relatorio.\n\nAbraço",
          quoted: "Em ter., 3 de nov. de 2026 às 10:00, Ana escreveu:\n> Pode mandar?", cached: true))
      responses["GET /api/notes/folders"] = try encoder.encode(
        NoteFoldersResponse(folders: [
          NoteFolder(id: "f1", name: "Trabalho", parentId: nil, position: 0, updatedAt: "2026-11-04T10:00:00.000Z")
        ]))
    } catch {
      Logger(subsystem: "io.github.novaisvictor.dailyweb", category: "FeatureEmail")
        .fault("Preview fixtures failed to encode: \(String(describing: error), privacy: .public)")
    }
    return responses
  }
}
