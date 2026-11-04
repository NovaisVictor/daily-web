import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
  /// Declared in `Config/Info.plist` (`UTExportedTypeDeclarations`).
  nonisolated static let dailyEmailDrag = UTType(exportedAs: "io.github.novaisvictor.dailyweb.email-drag")
}

/// What a dragged row carries: only the conversation that started the drag.
/// The batch itself is the store's selection, so the drop acts on what is on
/// screen and never on a stale copy (`EMAIL_DRAG_TYPE` in `FolderTree.tsx`).
nonisolated struct EmailDragToken: Codable, Sendable, Equatable {
  var threadID: String

  init(threadID: String) {
    self.threadID = threadID
  }
}

nonisolated extension EmailDragToken: Transferable {
  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .dailyEmailDrag)
  }
}
