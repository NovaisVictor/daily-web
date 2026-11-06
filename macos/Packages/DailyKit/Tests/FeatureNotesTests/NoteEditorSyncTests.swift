import Foundation
import Testing

@testable import FeatureNotes

/// When the note's text view may take the model's text (the paste that vanished).
@Suite struct NoteEditorSyncTests {
  @Test func aNoteSwitchReplacesAndStartsAtTheTop() {
    let sync = NoteEditorSync.decide(
      switched: true, modelText: "b", viewText: "a", lastModelText: "a", lastEmitted: "a")
    #expect(sync == .replace(preserveSelection: false))
  }

  @Test func theEchoOfTheEditorsOwnTextKeepsTheView() {
    let sync = NoteEditorSync.decide(
      switched: false, modelText: "abc", viewText: "abc", lastModelText: "ab", lastEmitted: "abc")
    #expect(sync == .keep)
  }

  @Test func aPasteTheStoreDidNotTakeIsNotErased() {
    let sync = NoteEditorSync.decide(
      switched: false, modelText: "old", viewText: "old pasted", lastModelText: "old", lastEmitted: "old pasted")
    #expect(sync == .keep)
  }

  @Test func aLateEchoOfAnEarlierKeystrokeKeepsTheNewerTyping() {
    let sync = NoteEditorSync.decide(
      switched: false, modelText: "abc", viewText: "abcd", lastModelText: "ab", lastEmitted: "abc")
    #expect(sync == .keep)
  }

  @Test func aChangeFromTheOtherEditorReplacesKeepingTheSelection() {
    let sync = NoteEditorSync.decide(
      switched: false, modelText: "typed in the sheet", viewText: "typed", lastModelText: "typed",
      lastEmitted: nil)
    #expect(sync == .replace(preserveSelection: true))
  }

  @Test func theSelectionStaysInsideShorterText() {
    #expect(NoteEditorSync.clamp(NSRange(location: 2, length: 3), to: 10) == NSRange(location: 2, length: 3))
    #expect(NoteEditorSync.clamp(NSRange(location: 8, length: 5), to: 10) == NSRange(location: 8, length: 2))
    #expect(NoteEditorSync.clamp(NSRange(location: 12, length: 4), to: 10) == NSRange(location: 10, length: 0))
    #expect(NoteEditorSync.clamp(NSRange(location: 0, length: 0), to: 0) == NSRange(location: 0, length: 0))
  }
}
