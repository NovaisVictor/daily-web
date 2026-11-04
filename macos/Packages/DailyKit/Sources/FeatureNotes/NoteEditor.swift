import AppKit
import DailyDesign
import SwiftUI

/// Lets the toolbar format the text view the editor created.
@MainActor
final class NoteEditorController {
  fileprivate weak var textView: MarkdownTextView?

  func apply(_ action: MarkdownAction) {
    textView?.format(action)
  }

  func focus() {
    guard let textView else { return }
    textView.window?.makeFirstResponder(textView)
  }
}

/// The note's text: a plain `NSTextView`, because the Markdown shortcuts and list
/// continuation need the selection and must go through native undo, as the web
/// does with `execCommand('insertText')` (`NotesPanel.tsx:325-346`).
struct NoteEditor: NSViewRepresentable {
  let noteID: String
  let text: String
  let accessibilityLabel: String
  let controller: NoteEditorController
  let onChange: (String) -> Void
  let onBlur: () -> Void
  @Environment(\.theme) private var theme

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder

    let textView = MarkdownTextView()
    textView.isRichText = false
    textView.allowsUndo = true
    textView.importsGraphics = false
    textView.drawsBackground = false
    // Markdown is typed literally: no curly quotes, dashes or replacements.
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    textView.textContainerInset = NSSize(width: 6, height: 8)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.delegate = context.coordinator
    scrollView.documentView = textView

    controller.textView = textView
    context.coordinator.textView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? MarkdownTextView else { return }
    let coordinator = context.coordinator
    coordinator.onChange = onChange
    coordinator.onBlur = onBlur
    controller.textView = textView
    textView.textColor = NSColor(theme.ink)
    textView.insertionPointColor = NSColor(theme.brand)
    textView.setAccessibilityLabel(accessibilityLabel)

    let switched = coordinator.noteID != noteID
    if switched || textView.string != text {
      textView.string = text
      textView.setSelectedRange(NSRange(location: 0, length: 0))
    }
    if switched {
      coordinator.noteID = noteID
      // Undo must not reach back into the previous note's text.
      textView.undoManager?.removeAllActions(withTarget: textView)
      if let storage = textView.textStorage { textView.undoManager?.removeAllActions(withTarget: storage) }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var noteID: String?
    var onChange: (String) -> Void = { _ in }
    var onBlur: () -> Void = {}
    weak var textView: MarkdownTextView?

    func textDidChange(_ notification: Notification) {
      guard let textView else { return }
      onChange(textView.string)
    }

    func textDidEndEditing(_ notification: Notification) {
      onBlur()
    }
  }
}

/// Adds the web's key map and list continuation to the plain text view.
final class MarkdownTextView: NSTextView {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === self, !hasMarkedText(), let action = Self.action(for: event) else {
      return super.performKeyEquivalent(with: event)
    }
    format(action)
    return true
  }

  override func insertNewline(_ sender: Any?) {
    let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
    let plainReturn = modifiers.isDisjoint(with: [.shift, .command, .option, .control])
    let selection = selectedRange()
    if plainReturn, !hasMarkedText(),
      let edit = MarkdownEditing.continueList(
        string, selection: TextSelection(start: selection.location, end: NSMaxRange(selection)))
    {
      apply(edit)
      return
    }
    super.insertNewline(sender)
  }

  func format(_ action: MarkdownAction) {
    let selection = selectedRange()
    apply(
      MarkdownEditing.format(
        string, selection: TextSelection(start: selection.location, end: NSMaxRange(selection)), action: action))
  }

  /// Replaces through the text system so the change lands on the undo stack and
  /// the delegate hears about it like any keystroke.
  private func apply(_ edit: TextEdit) {
    let range = NSRange(location: edit.from, length: edit.to - edit.from)
    guard shouldChangeText(in: range, replacementString: edit.insert) else { return }
    replaceCharacters(in: range, with: edit.insert)
    didChangeText()
    setSelectedRange(NSRange(location: edit.selection.start, length: edit.selection.end - edit.selection.start))
    scrollRangeToVisible(selectedRange())
  }

  private static func action(for event: NSEvent) -> MarkdownAction? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard let key = event.charactersIgnoringModifiers else { return nil }
    return MarkdownEditing.shortcut(
      key: key,
      command: flags.contains(.command),
      shift: flags.contains(.shift),
      option: flags.contains(.option),
      control: flags.contains(.control))
  }
}
