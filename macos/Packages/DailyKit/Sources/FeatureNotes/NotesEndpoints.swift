import DailyAPI
import DailyModels
import Foundation

/// The notes calls (`app/api/notes/**`, `docs/contracts/api.md`, "Notas").
nonisolated enum NotesEndpoints {
  /// `GET /api/notes`: notes, folders and the Drive copy's status.
  static var list: Endpoint<NotesResponse> { Endpoint(.get, "/api/notes") }

  /// `GET /api/notes/sync`: only the status, so a poll never overwrites a draft.
  static var sync: Endpoint<NotesSyncResponse> { Endpoint(.get, "/api/notes/sync") }

  static func create(title: String, folderId: String?) -> Endpoint<NoteResponse> {
    Endpoint(.post, "/api/notes", body: CreateNoteBody(title: title, folderId: folderId))
  }

  /// The whole order goes up: a position only means something next to the others
  /// (`app/api/notes/route.ts:39-40`).
  static func reorder(ids: [String]) -> Endpoint<NoteListResponse> {
    Endpoint(.put, "/api/notes", body: ReorderBody(ids: ids))
  }

  static func update(id: String, title: String? = nil, body: String? = nil) -> Endpoint<NoteResponse> {
    Endpoint(.patch, notePath(id), body: NoteTextBody(title: title, body: body))
  }

  static func move(id: String, folderId: String?) -> Endpoint<NoteResponse> {
    Endpoint(.patch, notePath(id), body: MoveNoteBody(folderId: folderId))
  }

  static func delete(id: String) -> Endpoint<EmptyResponse> {
    Endpoint(.delete, notePath(id))
  }

  static func createFolder(name: String, parentId: String?) -> Endpoint<NoteFolderResponse> {
    Endpoint(.post, "/api/notes/folders", body: CreateFolderBody(name: name, parentId: parentId))
  }

  static func renameFolder(id: String, name: String) -> Endpoint<NoteFolderResponse> {
    Endpoint(.patch, folderPath(id), body: RenameFolderBody(name: name))
  }

  static func moveFolder(id: String, parentId: String?) -> Endpoint<NoteFolderResponse> {
    Endpoint(.patch, folderPath(id), body: MoveFolderBody(parentId: parentId))
  }

  /// The notes inside go to "Sem pasta"; subfolders go with it.
  static func deleteFolder(id: String) -> Endpoint<EmptyResponse> {
    Endpoint(.delete, folderPath(id))
  }

  private static func notePath(_ id: String) -> String {
    "/api/notes/\(Endpoint<EmptyResponse>.segment(id))"
  }

  private static func folderPath(_ id: String) -> String {
    "/api/notes/folders/\(Endpoint<EmptyResponse>.segment(id))"
  }
}

// MARK: - Bodies

/// The web sends `folderId: null` for a loose note (`NotesPanel.tsx:388`).
nonisolated struct CreateNoteBody: Encodable, Sendable {
  let title: String
  let folderId: String?

  enum CodingKeys: String, CodingKey { case title, folderId }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encodeNullable(folderId, forKey: .folderId)
  }
}

nonisolated struct ReorderBody: Encodable, Sendable {
  let ids: [String]
}

/// Absent keys are left as they are on the server, so nil fields are omitted.
nonisolated struct NoteTextBody: Encodable, Sendable {
  let title: String?
  let body: String?
}

/// `folderId: null` takes the note out of every folder, while a missing key would
/// leave it where it is (`app/api/notes/[id]/route.ts:13-16`): null must be sent.
nonisolated struct MoveNoteBody: Encodable, Sendable {
  let folderId: String?

  enum CodingKeys: String, CodingKey { case folderId }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeNullable(folderId, forKey: .folderId)
  }
}

nonisolated struct CreateFolderBody: Encodable, Sendable {
  let name: String
  let parentId: String?

  enum CodingKeys: String, CodingKey { case name, parentId }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encodeNullable(parentId, forKey: .parentId)
  }
}

nonisolated struct RenameFolderBody: Encodable, Sendable {
  let name: String
}

/// Same rule as `MoveNoteBody`: `parentId: null` moves the folder to the root.
nonisolated struct MoveFolderBody: Encodable, Sendable {
  let parentId: String?

  enum CodingKeys: String, CodingKey { case parentId }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeNullable(parentId, forKey: .parentId)
  }
}

nonisolated extension KeyedEncodingContainer {
  /// Writes `null` for nil instead of omitting the key.
  fileprivate mutating func encodeNullable(_ value: String?, forKey key: Key) throws {
    if let value {
      try encode(value, forKey: key)
    } else {
      try encodeNil(forKey: key)
    }
  }
}
