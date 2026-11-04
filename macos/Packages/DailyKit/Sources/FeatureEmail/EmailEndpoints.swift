import DailyAPI
import DailyModels
import Foundation

/// One message an action is about: the IMAP uid only means something inside
/// its account (`components/EmailPanel.tsx`, `postBatch`).
nonisolated struct EmailTarget: Codable, Sendable, Equatable, Hashable {
  var account: String
  var id: String

  init(account: String, id: String) {
    self.account = account
    self.id = id
  }

  init(_ envelope: EmailEnvelope) {
    self.init(account: envelope.account, id: envelope.id)
  }
}

/// `move` takes the message out of its folder; `tag` copies it, which is what
/// Gmail calls a label (`app/api/email/batch/route.ts:18-20`).
nonisolated enum EmailBatchAction: String, Codable, Sendable, Equatable {
  case read
  case unread
  case move
  case tag
  case delete
}

/// The calls of the e-mail screen (`app/api/email/**`).
nonisolated enum EmailEndpoints {
  /// The inbox path on the server; the uid only identifies inside one folder.
  static let inboxPath = "INBOX"

  struct BatchBody: Encodable, Sendable, Equatable {
    let targets: [EmailTarget]
    let action: EmailBatchAction
    /// The destination of `move` and `tag`; absent for the others.
    let folder: String?
    /// The folder the messages are in.
    let folderPath: String
  }

  struct MarkBody: Encodable, Sendable, Equatable {
    let account: String
    let id: String
    let folder: String
    let seen: Bool
  }

  struct FolderReadBody: Encodable, Sendable, Equatable {
    let account: String
    let folder: String
  }

  struct DraftBody: Encodable, Sendable, Equatable {
    let account: String
    let id: String
    let from: String
    let subject: String
    let instruction: String
  }

  struct ReplyBody: Encodable, Sendable, Equatable {
    let account: String
    let id: String
    let body: String
  }

  struct ToNoteBody: Encodable, Sendable, Equatable {
    let account: String
    let id: String
    let folder: String
    let folderId: String?
  }

  struct ToTaskBody: Encodable, Sendable, Equatable {
    let account: String
    let id: String
    let folder: String
  }

  /// The stored tree answers at once; `sync=1` reads the server
  /// (`app/api/email/mailboxes/route.ts`).
  static func mailboxes(account: String, sync: Bool) -> Endpoint<MailboxesResponse> {
    var query = [URLQueryItem(name: "account", value: account)]
    if sync { query.append(URLQueryItem(name: "sync", value: "1")) }
    return Endpoint(.get, "/api/email/mailboxes", query: query)
  }

  static func folders(account: String) -> Endpoint<EmailFoldersResponse> {
    Endpoint(.get, "/api/email/folders", query: [URLQueryItem(name: "account", value: account)])
  }

  static func messages(account: String, folder: String) -> Endpoint<EmailMessagesResponse> {
    Endpoint(
      .get, "/api/email/messages",
      query: [URLQueryItem(name: "account", value: account), URLQueryItem(name: "folder", value: folder)])
  }

  /// The box goes along: the same uid exists in the inbox and in the sent folder.
  static func body(account: String, id: String, box: MailboxKind) -> Endpoint<EmailBody> {
    Endpoint(
      .get, "/api/email/\(Endpoint<EmailBody>.segment(account))/\(Endpoint<EmailBody>.segment(id))/body",
      query: [URLQueryItem(name: "box", value: box.rawValue)])
  }

  /// Always 200 with one result per target (`app/api/email/batch/route.ts:131`).
  static func batch(
    _ targets: [EmailTarget], action: EmailBatchAction, folder: String?, folderPath: String
  ) -> Endpoint<EmailBatchResponse> {
    Endpoint(
      .post, "/api/email/batch",
      body: BatchBody(targets: targets, action: action, folder: folder, folderPath: folderPath))
  }

  static func mark(_ envelope: EmailEnvelope, seen: Bool) -> Endpoint<EmptyResponse> {
    Endpoint(
      .post, "/api/email/mark",
      body: MarkBody(account: envelope.account, id: envelope.id, folder: envelope.folder, seen: seen))
  }

  static func folderRead(account: String, folder: String) -> Endpoint<EmptyResponse> {
    Endpoint(.post, "/api/email/folder/read", body: FolderReadBody(account: account, folder: folder))
  }

  /// Whatever is already typed becomes the instruction for the draft
  /// (`EmailPanel.tsx`, `draftWithAi`).
  static func replyDraft(_ envelope: EmailEnvelope, instruction: String) -> Endpoint<EmailDraftResponse> {
    Endpoint(
      .post, "/api/email/reply/draft",
      body: DraftBody(
        account: envelope.account, id: envelope.id, from: envelope.from, subject: envelope.subject,
        instruction: instruction))
  }

  static func reply(_ envelope: EmailEnvelope, body: String) -> Endpoint<EmptyResponse> {
    Endpoint(.post, "/api/email/reply", body: ReplyBody(account: envelope.account, id: envelope.id, body: body))
  }

  static func toNote(_ envelope: EmailEnvelope, noteFolderId: String?) -> Endpoint<EmailToNoteResponse> {
    Endpoint(
      .post, "/api/email/to-note",
      body: ToNoteBody(
        account: envelope.account, id: envelope.id, folder: envelope.folder, folderId: noteFolderId))
  }

  static func toTask(_ envelope: EmailEnvelope) -> Endpoint<EmailToTaskResponse> {
    Endpoint(
      .post, "/api/email/to-task",
      body: ToTaskBody(account: envelope.account, id: envelope.id, folder: envelope.folder))
  }

  /// The notes folders, for the "Pasta da nota" choice.
  static var noteFolders: Endpoint<NoteFoldersResponse> {
    Endpoint(.get, "/api/notes/folders")
  }
}
