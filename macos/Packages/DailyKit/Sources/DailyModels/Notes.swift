/// A notebook tab (`lib/types.ts:327-335`).
public struct Note: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var title: String
  public var body: String
  public var position: Int
  public var updatedAt: String
  /// Null when the note is loose ("Sem pasta").
  public var folderId: String?

  public init(id: String, title: String, body: String, position: Int, updatedAt: String, folderId: String?) {
    self.id = id
    self.title = title
    self.body = body
    self.position = position
    self.updatedAt = updatedAt
    self.folderId = folderId
  }
}

/// A notes folder; `parentId` null is a root folder (`lib/types.ts:338-344`).
public struct NoteFolder: Codable, Sendable, Equatable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var parentId: String?
  public var position: Int
  public var updatedAt: String

  public init(id: String, name: String, parentId: String?, position: Int, updatedAt: String) {
    self.id = id
    self.name = name
    self.parentId = parentId
    self.position = position
    self.updatedAt = updatedAt
  }
}

/// The Google Drive copy of the notes (`lib/notesSync.ts:35-41`).
public struct NotesSyncStatus: Codable, Sendable, Equatable, Hashable {
  public var connected: Bool
  public var account: String
  public var pending: Int
  public var lastError: String?
  public var lastSyncedAt: String?

  public init(connected: Bool, account: String, pending: Int, lastError: String?, lastSyncedAt: String?) {
    self.connected = connected
    self.account = account
    self.pending = pending
    self.lastError = lastError
    self.lastSyncedAt = lastSyncedAt
  }
}

/// `GET /api/notes` (`app/api/notes/route.ts:15`).
public struct NotesResponse: Codable, Sendable, Equatable, Hashable {
  public var notes: [Note]
  public var folders: [NoteFolder]
  public var sync: NotesSyncStatus

  public init(notes: [Note], folders: [NoteFolder], sync: NotesSyncStatus) {
    self.notes = notes
    self.folders = folders
    self.sync = sync
  }
}

/// `POST /api/notes` and `PATCH /api/notes/{id}` (`app/api/notes/route.ts:29`,
/// `app/api/notes/[id]/route.ts:41`).
public struct NoteResponse: Codable, Sendable, Equatable, Hashable {
  public var note: Note

  public init(note: Note) {
    self.note = note
  }
}

/// `PUT /api/notes`, the reordered list (`app/api/notes/route.ts:51`).
public struct NoteListResponse: Codable, Sendable, Equatable, Hashable {
  public var notes: [Note]

  public init(notes: [Note]) {
    self.notes = notes
  }
}

/// `GET /api/notes/sync` (`app/api/notes/sync/route.ts:10`).
public struct NotesSyncResponse: Codable, Sendable, Equatable, Hashable {
  public var sync: NotesSyncStatus

  public init(sync: NotesSyncStatus) {
    self.sync = sync
  }
}

/// `GET /api/notes/folders` (`app/api/notes/folders/route.ts:10`).
public struct NoteFoldersResponse: Codable, Sendable, Equatable, Hashable {
  public var folders: [NoteFolder]

  public init(folders: [NoteFolder]) {
    self.folders = folders
  }
}

/// `POST /api/notes/folders` and `PATCH /api/notes/folders/{id}`
/// (`app/api/notes/folders/route.ts:29`, `app/api/notes/folders/[id]/route.ts:38`).
public struct NoteFolderResponse: Codable, Sendable, Equatable, Hashable {
  public var folder: NoteFolder

  public init(folder: NoteFolder) {
    self.folder = folder
  }
}
