import DailyModels
import Foundation

/// What the sidebar shows (`components/notes/NoteTree.tsx:30`). "Todas" and
/// "Sem pasta" are not folders on the server: they are the two views that always exist.
enum NoteScope: Hashable, Sendable {
  case all
  case none
  case folder(String)

  var folderID: String? {
    if case .folder(let id) = self { id } else { nil }
  }
}

/// A folder placed in the hierarchy.
struct NoteFolderNode: Equatable, Identifiable {
  var folder: NoteFolder
  var depth: Int
  var children: [NoteFolderNode]

  var id: String { folder.id }
}

/// Why a folder cannot go where it was dropped (`lib/notesTree.ts:114`).
enum FolderMoveRefusal: Equatable {
  case unknown
  case cycle
  case depth

  /// The server's own text for the same refusal (`lib/noteFolders.ts:23-27`).
  var message: String {
    switch self {
    case .unknown: "pasta não encontrada"
    case .cycle: "uma pasta não pode ir para dentro de si mesma"
    case .depth: "a hierarquia de pastas ficou funda demais"
    }
  }
}

/// The folder hierarchy rules, mirrored from `lib/notesTree.ts`.
enum NotesTree {
  /// `MAX_FOLDER_DEPTH`: deeper than this the indentation eats the width.
  static let maxDepth = 5
  static let maxFolders = 100

  /// Builds the hierarchy from the flat list. A folder whose parent is missing, or
  /// that reaches itself through its parents, goes to the root instead of
  /// vanishing: no note may become unreachable.
  static func build(_ folders: [NoteFolder]) -> [NoteFolderNode] {
    let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let order = Dictionary(folders.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    var children: [String: [NoteFolder]] = [:]
    var roots: [NoteFolder] = []
    for folder in folders {
      if let parentId = folder.parentId, byID[parentId] != nil,
        !isAncestor(byID, id: folder.id, candidate: parentId)
      {
        children[parentId, default: []].append(folder)
      } else {
        roots.append(folder)
      }
    }

    func sorted(_ list: [NoteFolder]) -> [NoteFolder] {
      list.sorted { a, b in
        if a.position != b.position { return a.position < b.position }
        let byName = a.name.localizedCompare(b.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return (order[a.id] ?? 0) < (order[b.id] ?? 0)
      }
    }

    var visited: Set<String> = []
    func node(_ folder: NoteFolder, depth: Int) -> NoteFolderNode {
      visited.insert(folder.id)
      let kids = sorted(children[folder.id] ?? []).filter { !visited.contains($0.id) }
      return NoteFolderNode(folder: folder, depth: depth, children: kids.map { node($0, depth: depth + 1) })
    }
    return sorted(roots).map { node($0, depth: 0) }
  }

  /// Is `candidate` below `id`? Walks up from the candidate with a step limit, so
  /// a cycle stored on the server cannot hang here.
  private static func isAncestor(_ byID: [String: NoteFolder], id: String, candidate: String) -> Bool {
    var current: String? = candidate
    var step = 0
    while step <= byID.count, let value = current {
      if value == id { return true }
      current = byID[value]?.parentId
      step += 1
    }
    return false
  }

  /// The folder and everything inside it. Unknown ids answer nothing.
  static func descendantIDs(_ folders: [NoteFolder], of id: String) -> [String] {
    guard folders.contains(where: { $0.id == id }) else { return [] }
    var byParent: [String: [NoteFolder]] = [:]
    for folder in folders {
      if let parentId = folder.parentId { byParent[parentId, default: []].append(folder) }
    }
    var out: [String] = []
    var seen: Set<String> = []
    func walk(_ folderID: String) {
      guard seen.insert(folderID).inserted else { return }
      out.append(folderID)
      for child in byParent[folderID] ?? [] { walk(child.id) }
    }
    walk(id)
    return out
  }

  /// The readable path from the root inward: ["Trabalho", "Clientes"].
  static func path(_ folders: [NoteFolder], to id: String?) -> [String] {
    let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var names: [String] = []
    var current = id
    var step = 0
    while step < byID.count, let value = current, let folder = byID[value] {
      names.insert(folder.name, at: 0)
      current = folder.parentId
      step += 1
    }
    return names
  }

  /// Depth in the tree; the root is 0.
  static func depth(_ folders: [NoteFolder], of id: String?) -> Int {
    max(0, path(folders, to: id).count - 1)
  }

  /// Height of the subtree: 1 for a folder without children.
  static func height(_ folders: [NoteFolder], of id: String) -> Int {
    var seen: Set<String> = []
    func measure(_ folderID: String) -> Int {
      guard seen.insert(folderID).inserted else { return 0 }
      let kids = folders.filter { $0.parentId == folderID }
      guard !kids.isEmpty else { return 1 }
      return 1 + (kids.map { measure($0.id) }.max() ?? 0)
    }
    return measure(id)
  }

  /// Can `id` go inside `parentId`? nil when it can.
  static func refuseMove(_ folders: [NoteFolder], id: String, to parentId: String?) -> FolderMoveRefusal? {
    guard folders.contains(where: { $0.id == id }) else { return .unknown }
    guard let parentId else {
      return height(folders, of: id) > maxDepth ? .depth : nil
    }
    guard folders.contains(where: { $0.id == parentId }) else { return .unknown }
    if descendantIDs(folders, of: id).contains(parentId) { return .cycle }
    if depth(folders, of: parentId) + 1 + height(folders, of: id) > maxDepth { return .depth }
    return nil
  }

  /// The confirmation for deleting a folder (`NotesPanel.tsx:535-557`).
  static func deletionPrompt(
    for folder: NoteFolder, folders: [NoteFolder], notes: [Note]
  ) -> (title: String, message: String, confirmLabel: String) {
    let inside = Set(descendantIDs(folders, of: folder.id))
    let subfolders = max(0, inside.count - 1)
    let notesInside = notes.filter { note in note.folderId.map(inside.contains) ?? false }.count

    var effect: [String] = []
    if subfolders > 0 { effect.append("\(subfolders) \(subfolders == 1 ? "subpasta" : "subpastas")") }
    if notesInside > 0 { effect.append("\(notesInside) \(notesInside == 1 ? "nota" : "notas")") }

    let message: String
    if effect.isEmpty {
      message = "A pasta está vazia e será removida."
    } else {
      let moved = notesInside > 0 ? "Nenhuma nota é apagada: todas vão para \"Sem pasta\". " : ""
      let removed = subfolders > 0 ? "As subpastas são removidas junto." : ""
      message = "A pasta tem \(effect.joined(separator: " e ")). \(moved)\(removed)"
    }
    return (
      "Apagar a pasta \"\(folder.name)\"?",
      message,
      notesInside > 0 ? "Apagar e mover para Sem pasta" : "Apagar"
    )
  }
}

/// One line of the sidebar, in display order.
enum NoteTreeRow: Identifiable, Equatable {
  case all(count: Int)
  case none(count: Int, expanded: Bool)
  case folder(NoteFolder, depth: Int, noteCount: Int, expanded: Bool)
  case note(Note, depth: Int)
  /// "pasta vazia" under an open folder with nothing inside.
  case empty(folderID: String, depth: Int)

  static let allKey = "__all__"
  static let noneKey = "__none__"

  static func noteKey(_ id: String) -> String { "note:\(id)" }
  static func folderKey(_ id: String) -> String { "folder:\(id)" }

  var id: String {
    switch self {
    case .all: Self.allKey
    case .none: Self.noneKey
    case .folder(let folder, _, _, _): Self.folderKey(folder.id)
    case .note(let note, _): Self.noteKey(note.id)
    case .empty(let folderID, _): "empty:\(folderID)"
    }
  }

  /// The visible rows: "Todas as notas", "Sem pasta" with its loose notes, then
  /// the folders. Each note shows once, under its folder or under "Sem pasta".
  /// `expanded` holds folder ids and `NoteTreeRow.noneKey`.
  static func flatten(notes: [Note], folders: [NoteFolder], expanded: Set<String>) -> [NoteTreeRow] {
    let known = Set(folders.map(\.id))
    // A note pointing at a folder we do not have is shown as loose rather than lost.
    let loose = notes.filter { note in note.folderId.map { !known.contains($0) } ?? true }
    var rows: [NoteTreeRow] = [.all(count: notes.count)]
    let noneOpen = expanded.contains(noneKey)
    rows.append(.none(count: loose.count, expanded: noneOpen))
    if noneOpen { rows += loose.map { .note($0, depth: 1) } }

    func append(_ node: NoteFolderNode) {
      let inside = notes.filter { $0.folderId == node.id }
      let open = expanded.contains(node.id)
      rows.append(.folder(node.folder, depth: node.depth, noteCount: inside.count, expanded: open))
      guard open else { return }
      node.children.forEach(append)
      rows += inside.map { .note($0, depth: node.depth + 1) }
      if node.children.isEmpty && inside.isEmpty {
        rows.append(.empty(folderID: node.id, depth: node.depth))
      }
    }
    NotesTree.build(folders).forEach(append)
    return rows
  }
}
