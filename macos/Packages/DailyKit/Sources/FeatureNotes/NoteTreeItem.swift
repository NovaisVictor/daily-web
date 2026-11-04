import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
  /// A content type of its own, so a folder accepts notes and folders from this
  /// tree and nothing else (`NOTE_DRAG_TYPE` and `FOLDER_DRAG_TYPE` on the web).
  nonisolated static let dailyNoteTreeItem = UTType(exportedAs: "io.github.novaisvictor.dailyweb.note-tree-item")
}

/// What is dragged inside the notes sidebar.
nonisolated enum NoteTreeItem: Codable, Hashable, Sendable, Transferable {
  case note(String)
  case folder(String)

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .dailyNoteTreeItem)
  }
}
