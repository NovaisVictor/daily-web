import AppKit
import DailyModels
import SwiftUI
import Testing

@testable import FeatureNotes

/// The "…" menu (`NoteTree.tsx` `NoteMenu`/`FolderMenu`) and the row keys.
@MainActor
@Suite struct NoteTreeActionsTests {
  let folders = [folder("f1", name: "Trabalho"), folder("f2", parent: "f1", name: "Clientes")]

  @Test func noteMenuListsEveryDestinationByItsPath() {
    let items = NoteTreeActions.items(
      for: note("n1", "Ata", folder: "f1"), folders: folders, canShiftUp: false, canShiftDown: true)
    #expect(
      items.map(\.label) == [
        "Renomear", "Mover para Sem pasta", "Mover para Trabalho / Clientes", "Mover para cima",
        "Mover para baixo", "Apagar nota",
      ])
    #expect(items.first { $0.action == .shiftNote(by: -1) }?.isEnabled == false)
    #expect(items.first { $0.action == .shiftNote(by: 1) }?.isEnabled == true)
    #expect(items.last?.isDestructive == true)
  }

  @Test func looseNoteHasNoMoveToSemPasta() {
    let items = NoteTreeActions.items(for: note("n1"), folders: folders, canShiftUp: true, canShiftDown: true)
    #expect(!items.map(\.action).contains(.moveNote(to: nil)))
    #expect(items.contains { $0.action == .moveNote(to: "f1") && $0.shortLabel == "Trabalho" })
  }

  @Test func folderMenuSkipsItselfAndItsParent() {
    let items = NoteTreeActions.items(for: folders[1], folders: folders + [folder("f3", name: "Casa")])
    #expect(
      items.map(\.label) == ["Renomear", "Nova subpasta", "Mover para a raiz", "Mover para Casa", "Apagar pasta"])
    #expect(items.first { $0.action == .moveFolder(to: nil) }?.isEnabled == true)
  }

  @Test func rootFolderCannotMoveToTheRoot() {
    let items = NoteTreeActions.items(for: folders[0], folders: folders)
    #expect(items.first { $0.action == .moveFolder(to: nil) }?.isEnabled == false)
  }

  @Test func buttonLabelsMatchTheWeb() {
    #expect(NoteTreeActions.label(for: note("n1", "Ata")) == "ações de Ata")
    #expect(NoteTreeActions.label(for: note("n1")) == "ações de sem título")
    #expect(NoteTreeActions.label(for: folders[0]) == "ações da pasta Trabalho")
  }

  @Test func rowKeysMapToActions() {
    func command(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> NoteTreeShortcut? {
      NoteTreeShortcut.command(character: key.character, modifiers: modifiers)
    }
    #expect(command(.return, []) == .rename)
    #expect(command(.return, .control) == .showActions)
    #expect(command(.delete, .command) == .delete)
    #expect(command(.upArrow, [.command, .option, .numericPad]) == .shift(by: -1))
    #expect(command(.downArrow, [.command, .option]) == .shift(by: 1))
    #expect(command("n", [.command, .option]) == .newSubfolder)
    // Plain keys stay with the list: arrows move, Delete alone does nothing.
    #expect(command(.delete, []) == nil)
    #expect(command(.upArrow, []) == nil)
    #expect(command(.upArrow, .command) == nil)
    #expect(command(.return, .shift) == nil)
  }

  /// ⌘K inserts a link when the editor has focus: the window's views see a key
  /// equivalent before the main menu, so returning true keeps the palette shut.
  @Test func commandKInTheFocusedEditorInsertsALink() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered,
      defer: true)
    let textView = MarkdownTextView(frame: window.contentLayoutRect)
    window.contentView = textView
    textView.string = "site"
    textView.setSelectedRange(NSRange(location: 0, length: 4))
    let event = try #require(commandK(window))

    #expect(window.makeFirstResponder(nil))
    #expect(textView.performKeyEquivalent(with: event) == false)
    #expect(textView.string == "site")

    #expect(window.makeFirstResponder(textView))
    #expect(window.performKeyEquivalent(with: event))
    #expect(textView.string.hasPrefix("[site]("))
  }

  private func commandK(_ window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)
  }
}
