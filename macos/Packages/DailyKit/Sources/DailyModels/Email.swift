/// Which of the two boxes a message came from (`lib/types.ts:35`). An IMAP uid
/// is per box, so no operation can use an id without it.
public struct MailboxKind: ServerEnum {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let inbox = MailboxKind(rawValue: "inbox")
  public static let sent = MailboxKind(rawValue: "sent")
  public static let known: [MailboxKind] = [.inbox, .sent]
}

/// One message in a list (`lib/types.ts:6-32`).
public struct EmailEnvelope: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var account: String
  public var accountLabel: String
  public var from: String
  public var subject: String
  public var unread: Bool
  public var date: String
  public var messageId: String
  public var references: [String]
  public var labels: [String]
  public var mailbox: MailboxKind
  public var folder: String
  /// Why the last action on this message failed for good, when it did.
  public var actionError: String?

  public init(
    id: String,
    account: String,
    accountLabel: String,
    from: String,
    subject: String,
    unread: Bool,
    date: String,
    messageId: String,
    references: [String],
    labels: [String],
    mailbox: MailboxKind,
    folder: String,
    actionError: String? = nil
  ) {
    self.id = id
    self.account = account
    self.accountLabel = accountLabel
    self.from = from
    self.subject = subject
    self.unread = unread
    self.date = date
    self.messageId = messageId
    self.references = references
    self.labels = labels
    self.mailbox = mailbox
    self.folder = folder
    self.actionError = actionError
  }
}

/// A server folder as the tree draws it (`lib/types.ts:38-49`).
public struct MailboxNode: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var path: String
  public var name: String
  public var delimiter: String
  public var parent: String?
  public var specialUse: String?
  public var total: Int
  public var unread: Int

  public var id: String { path }

  public init(
    path: String,
    name: String,
    delimiter: String,
    parent: String?,
    specialUse: String?,
    total: Int,
    unread: Int
  ) {
    self.path = path
    self.name = name
    self.delimiter = delimiter
    self.parent = parent
    self.specialUse = specialUse
    self.total = total
    self.unread = unread
  }
}

/// `GET /api/email/mailboxes` (`app/api/email/mailboxes/route.ts:19-34`).
/// `added` and `removed` only come with `sync=1`.
public struct MailboxesResponse: Codable, Sendable, Equatable, Hashable {
  public var mailboxes: [MailboxNode]
  public var syncedAt: String?
  public var cached: Bool
  public var added: [String]?
  public var removed: [String]?

  public init(
    mailboxes: [MailboxNode],
    syncedAt: String?,
    cached: Bool,
    added: [String]? = nil,
    removed: [String]? = nil
  ) {
    self.mailboxes = mailboxes
    self.syncedAt = syncedAt
    self.cached = cached
    self.added = added
    self.removed = removed
  }
}

/// `GET /api/email/folders` (`app/api/email/folders/route.ts:11`,
/// `lib/integrations/imap.ts:409`).
public struct EmailFoldersResponse: Codable, Sendable, Equatable, Hashable {
  public var folders: [String]

  public init(folders: [String]) {
    self.folders = folders
  }
}

/// `GET /api/email/messages` (`app/api/email/messages/route.ts:52-56`,
/// `lib/email/sync.ts:42-51`).
public struct EmailMessagesResponse: Codable, Sendable, Equatable, Hashable {
  public var messages: [EmailEnvelope]
  public var uidvalidity: String
  /// The server renumbered the folder, so everything cached was read again.
  public var reindexed: Bool

  public init(messages: [EmailEnvelope], uidvalidity: String, reindexed: Bool) {
    self.messages = messages
    self.uidvalidity = uidvalidity
    self.reindexed = reindexed
  }
}

/// `GET /api/email/{account}/{id}/body`: the plain text split into what was
/// written now and the quoted history (`lib/parsers/mail.ts:111-116`,
/// `app/api/email/[account]/[id]/body/route.ts:36,42`).
public struct EmailBody: Codable, Sendable, Equatable, Hashable {
  public var text: String
  /// Empty when there is no quoted history.
  public var quoted: String
  public var cached: Bool

  public init(text: String, quoted: String, cached: Bool) {
    self.text = text
    self.quoted = quoted
    self.cached = cached
  }
}

/// One target of `POST /api/email/batch` (`app/api/email/batch/route.ts:33-38`).
public struct EmailBatchResult: Codable, Sendable, Equatable, Hashable {
  public var account: String
  public var id: String
  public var ok: Bool
  public var error: String?

  public init(account: String, id: String, ok: Bool, error: String? = nil) {
    self.account = account
    self.id = id
    self.ok = ok
    self.error = error
  }
}

/// `POST /api/email/batch` (`app/api/email/batch/route.ts:131`).
public struct EmailBatchResponse: Codable, Sendable, Equatable, Hashable {
  public var results: [EmailBatchResult]

  public init(results: [EmailBatchResult]) {
    self.results = results
  }
}

/// `POST /api/email/to-note` (`app/api/email/to-note/route.ts:51,75`). A repeated
/// click answers with the first note's id only.
public struct EmailToNoteResponse: Codable, Sendable, Equatable, Hashable {
  public var noteId: String
  public var note: Note?
  public var repeated: Bool?

  public init(noteId: String, note: Note? = nil, repeated: Bool? = nil) {
    self.noteId = noteId
    self.note = note
    self.repeated = repeated
  }
}

/// `POST /api/email/to-task` (`app/api/email/to-task/route.ts:40,52`).
public struct EmailToTaskResponse: Codable, Sendable, Equatable, Hashable {
  public var taskId: String
  public var repeated: Bool?

  public init(taskId: String, repeated: Bool? = nil) {
    self.taskId = taskId
    self.repeated = repeated
  }
}

/// `POST /api/email/reply/draft` (`app/api/email/reply/draft/route.ts:34`).
public struct EmailDraftResponse: Codable, Sendable, Equatable, Hashable {
  public var text: String

  public init(text: String) {
    self.text = text
  }
}
