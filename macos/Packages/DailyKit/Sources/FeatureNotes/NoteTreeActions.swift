import DailyModels
import SwiftUI

/// What a tree row can do. The "…" button, the context menu and the keyboard
/// list all read the same entries, so none of them offers less than another.
enum NoteTreeAction: Hashable {
  case rename
  case newSubfolder
  /// nil: "Sem pasta".
  case moveNote(to: String?)
  /// nil: the root.
  case moveFolder(to: String?)
  /// -1 up, +1 down among the folder's notes.
  case shiftNote(by: Int)
  case deleteNote
  case deleteFolder

  var isMove: Bool {
    switch self {
    case .moveNote, .moveFolder: true
    default: false
    }
  }
}

struct NoteTreeMenuItem: Identifiable, Equatable {
  let action: NoteTreeAction
  /// The full label, as the web menu says it ("Mover para Trabalho / Clientes").
  let label: String
  /// The label inside the native "Mover para" submenu, without the prefix.
  let shortLabel: String
  var isEnabled = true
  var isDestructive = false

  var id: NoteTreeAction { action }
}

/// The entries of `NoteMenu` and `FolderMenu` (`components/notes/NoteTree.tsx`),
/// plus "Mover para cima/baixo", which the web only offers by dragging.
enum NoteTreeActions {
  static func items(for note: Note, folders: [NoteFolder], canShiftUp: Bool, canShiftDown: Bool)
    -> [NoteTreeMenuItem]
  {
    var items = [NoteTreeMenuItem(action: .rename, label: "Renomear", shortLabel: "Renomear")]
    if note.folderId != nil {
      items.append(move(.moveNote(to: nil), "Sem pasta"))
    }
    for target in folders where target.id != note.folderId {
      items.append(move(.moveNote(to: target.id), path(folders, target.id)))
    }
    items.append(
      NoteTreeMenuItem(
        action: .shiftNote(by: -1), label: "Mover para cima", shortLabel: "Mover para cima", isEnabled: canShiftUp))
    items.append(
      NoteTreeMenuItem(
        action: .shiftNote(by: 1), label: "Mover para baixo", shortLabel: "Mover para baixo", isEnabled: canShiftDown))
    items.append(
      NoteTreeMenuItem(action: .deleteNote, label: "Apagar nota", shortLabel: "Apagar nota", isDestructive: true))
    return items
  }

  static func items(for folder: NoteFolder, folders: [NoteFolder]) -> [NoteTreeMenuItem] {
    var items = [
      NoteTreeMenuItem(action: .rename, label: "Renomear", shortLabel: "Renomear"),
      NoteTreeMenuItem(action: .newSubfolder, label: "Nova subpasta", shortLabel: "Nova subpasta"),
    ]
    var root = move(.moveFolder(to: nil), "a raiz")
    root.isEnabled = folder.parentId != nil
    items.append(root)
    for target in folders where target.id != folder.id && target.id != folder.parentId {
      items.append(move(.moveFolder(to: target.id), path(folders, target.id)))
    }
    items.append(
      NoteTreeMenuItem(action: .deleteFolder, label: "Apagar pasta", shortLabel: "Apagar pasta", isDestructive: true))
    return items
  }

  /// The "…" button's name (`aria-label` in `NoteTree.tsx`).
  static func label(for note: Note) -> String { "ações de \(note.title.isEmpty ? "sem título" : note.title)" }

  static func label(for folder: NoteFolder) -> String { "ações da pasta \(folder.name)" }

  private static func move(_ action: NoteTreeAction, _ destination: String) -> NoteTreeMenuItem {
    NoteTreeMenuItem(action: action, label: "Mover para \(destination)", shortLabel: destination)
  }

  /// The whole path, so two "Clientes" in different branches stay apart.
  private static func path(_ folders: [NoteFolder], _ id: String) -> String {
    NotesTree.path(folders, to: id).joined(separator: " / ")
  }
}

/// The keys on the selected row of the tree: the keyboard way to every action
/// of the "…" menu, with the Finder's chords where one exists.
enum NoteTreeShortcut: Equatable {
  /// Return, as double click.
  case rename
  /// ⌘⌫, with confirmation, as the Finder's "Move to Trash".
  case delete
  /// ⌥⌘↑ and ⌥⌘↓.
  case shift(by: Int)
  /// ⌥⌘N.
  case newSubfolder
  /// ⌃Return opens the row's whole action list, "Mover para" included.
  case showActions

  static func command(character: Character, modifiers: EventModifiers) -> NoteTreeShortcut? {
    let chord = modifiers.intersection([.command, .option, .control, .shift])
    switch (character, chord) {
    case (KeyEquivalent.return.character, []): return .rename
    case (KeyEquivalent.return.character, .control): return .showActions
    case (KeyEquivalent.delete.character, .command), (KeyEquivalent.deleteForward.character, .command): return .delete
    case (KeyEquivalent.upArrow.character, [.command, .option]): return .shift(by: -1)
    case (KeyEquivalent.downArrow.character, [.command, .option]): return .shift(by: 1)
    case ("n", [.command, .option]), ("N", [.command, .option]): return .newSubfolder
    default: return nil
    }
  }
}
