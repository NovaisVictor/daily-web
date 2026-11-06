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
  /// Esc in the text; nil keeps the text view's own completion.
  var onEscape: (() -> Void)?
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
    // `font-mono leading-relaxed` (`NotesPanel.tsx:673`, NT-26): Geist Mono at the
    // textarea's `text-sm`, lines at 1.625.
    let font = NoteEditor.font
    textView.font = font
    textView.defaultParagraphStyle = NoteEditor.paragraphStyle(for: font)
    textView.typingAttributes[.paragraphStyle] = textView.defaultParagraphStyle
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
    textView.onEscape = onEscape
    textView.textColor = NSColor(theme.ink)
    textView.insertionPointColor = NSColor(theme.brand)
    textView.setAccessibilityLabel(accessibilityLabel)

    let switched = coordinator.noteID != noteID
    let sync = NoteEditorSync.decide(
      switched: switched,
      modelText: text,
      viewText: textView.string,
      lastModelText: coordinator.lastModelText,
      lastEmitted: coordinator.lastEmitted)
    coordinator.lastModelText = text
    switch sync {
    case .keep:
      break
    case .replace(let preserveSelection):
      let selection = textView.selectedRange()
      textView.string = text
      if let storage = textView.textStorage, let style = textView.defaultParagraphStyle {
        storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: storage.length))
      }
      textView.setSelectedRange(
        preserveSelection
          ? NoteEditorSync.clamp(selection, to: (text as NSString).length)
          : NSRange(location: 0, length: 0))
    }
    if switched {
      coordinator.noteID = noteID
      coordinator.lastEmitted = nil
      // Undo must not reach back into the previous note's text.
      textView.undoManager?.removeAllActions(withTarget: textView)
      if let storage = textView.textStorage { textView.undoManager?.removeAllActions(withTarget: storage) }
    }
  }

  /// The textarea's `text-sm`.
  static let fontSize: CGFloat = 14
  /// `leading-relaxed`.
  static let lineHeight: CGFloat = 1.625

  static var font: NSFont { DailyFonts.ctFont(.mono, size: fontSize, weight: .regular) as NSFont }

  /// Spacing after each line that brings the font's own line up to `leading-relaxed`.
  static func paragraphStyle(for font: NSFont) -> NSParagraphStyle {
    let natural = NSLayoutManager().defaultLineHeight(for: font)
    let style = NSMutableParagraphStyle()
    style.lineSpacing = max(0, font.pointSize * lineHeight - natural)
    return style
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var noteID: String?
    /// The model's text at the last update, to tell an outside change from a
    /// model that did not move (a refused edit leaves it behind the view).
    var lastModelText: String?
    /// What this editor last sent up, so its own echo never rewrites the view.
    var lastEmitted: String?
    var onChange: (String) -> Void = { _ in }
    var onBlur: () -> Void = {}
    weak var textView: MarkdownTextView?

    func textDidChange(_ notification: Notification) {
      guard let textView else { return }
      lastEmitted = textView.string
      onChange(textView.string)
    }

    func textDidEndEditing(_ notification: Notification) {
      onBlur()
    }
  }
}

/// Whether `updateNSView` may write the model's text into the text view.
/// Rewriting on every difference erased a paste the store had not taken yet and
/// threw the caret to the start; only a note switch or a change made elsewhere
/// (the other editor bound to the same draft, a reload) may replace the text.
enum NoteEditorSync: Equatable {
  case keep
  case replace(preserveSelection: Bool)

  static func decide(
    switched: Bool, modelText: String, viewText: String, lastModelText: String?, lastEmitted: String?
  ) -> NoteEditorSync {
    if switched { return .replace(preserveSelection: false) }
    if modelText == viewText { return .keep }
    // The model did not move since the last update: the view holds typing the
    // store has not taken, which must not be undone.
    if modelText == lastModelText { return .keep }
    // The store caught up with an earlier keystroke of this editor.
    if modelText == lastEmitted { return .keep }
    return .replace(preserveSelection: true)
  }

  /// The selection kept inside text that may have become shorter (UTF-16 units).
  static func clamp(_ selection: NSRange, to textLength: Int) -> NSRange {
    let start = min(max(0, selection.location), textLength)
    let end = min(max(start, selection.location + selection.length), textLength)
    return NSRange(location: start, length: end - start)
  }
}

/// Adds the web's key map and list continuation to the plain text view.
final class MarkdownTextView: NSTextView {
  /// The maximized note closes on Esc (`NotesPanel.tsx:839-844`); the text view
  /// would otherwise take Esc for word completion and keep it from the sheet.
  var onEscape: (() -> Void)?

  override func cancelOperation(_ sender: Any?) {
    guard let onEscape else {
      super.cancelOperation(sender)
      return
    }
    onEscape()
  }

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
