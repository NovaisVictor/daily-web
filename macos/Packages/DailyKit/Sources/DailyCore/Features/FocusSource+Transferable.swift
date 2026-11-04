import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
  /// Declared in `Config/Info.plist` (`UTExportedTypeDeclarations`), so only
  /// this app's drags are accepted by focus drop targets.
  public nonisolated static let dailyFocusSource = UTType(exportedAs: "io.github.novaisvictor.dailyweb.focus-source")
}

/// Tasks, Jira issues and pull requests are dragged onto the agenda to book a
/// focus block (`components/FocusBlockProvider.tsx`). The payload lives in core
/// so a feature can offer it and another accept it without importing each other.
nonisolated extension FocusSource: Transferable {
  public static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .dailyFocusSource)
  }
}
