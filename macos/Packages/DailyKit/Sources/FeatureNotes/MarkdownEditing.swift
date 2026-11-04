import Foundation

// Markdown formatting for the note editor, mirrored from `lib/markdown/editing.ts`.
// Pure functions over the text and the selection: each returns the smallest edit
// that produces the result, so the editor applies it through the text view and
// keeps native undo. Offsets are UTF-16 units, the same as `NSTextView`'s ranges
// and JavaScript's string indices.

/// A selection or caret, in UTF-16 offsets.
struct TextSelection: Equatable {
  var start: Int
  var end: Int
}

/// Replace `from..<to` with `insert`, then select `selection` (offsets in the new text).
struct TextEdit: Equatable {
  var from: Int
  var to: Int
  var insert: String
  var selection: TextSelection
}

enum MarkdownAction: String, CaseIterable, Identifiable {
  case heading, bold, italic, strike, code, link, bullet, ordered, task, quote, codeBlock

  var id: String { rawValue }

  /// Toolbar labels from `NotesPanel.tsx:85-97`, with the Mac's ⌘ for the web's Ctrl.
  var label: String {
    switch self {
    case .heading: "Título"
    case .bold: "Negrito (⌘B)"
    case .italic: "Itálico (⌘I)"
    case .strike: "Riscado (⌘⇧X)"
    case .code: "Código (⌘E)"
    case .link: "Link (⌘K)"
    case .bullet: "Lista"
    case .ordered: "Lista numerada"
    case .task: "Lista de tarefas"
    case .quote: "Citação"
    case .codeBlock: "Bloco de código"
    }
  }

  var systemImage: String {
    switch self {
    case .heading: "textformat.size"
    case .bold: "bold"
    case .italic: "italic"
    case .strike: "strikethrough"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .link: "link"
    case .bullet: "list.bullet"
    case .ordered: "list.number"
    case .task: "checklist"
    case .quote: "text.quote"
    case .codeBlock: "curlybraces.square"
    }
  }
}

enum MarkdownEditing {
  static func apply(_ edit: TextEdit, to text: String) -> String {
    let value = text as NSString
    return value.replacingCharacters(in: NSRange(location: edit.from, length: edit.to - edit.from), with: edit.insert)
  }

  /// The key map of `NotesPanel.tsx:100-109` on the Mac: ⌘B, ⌘I, ⌘E, ⌘K and
  /// ⌘⇧X. Control is left alone because Cocoa text views bind ⌃B, ⌃E and ⌃K to
  /// cursor movement and kill.
  static func shortcut(key: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> MarkdownAction? {
    guard command, !option, !control else { return nil }
    let key = key.lowercased()
    if shift { return key == "x" ? .strike : nil }
    switch key {
    case "b": return .bold
    case "i": return .italic
    case "k": return .link
    case "e": return .code
    default: return nil
    }
  }

  static func format(_ text: String, selection: TextSelection, action: MarkdownAction) -> TextEdit {
    let source = Source(text)
    switch action {
    case .bold: return wrap(source, selection, marker: "**", placeholder: "negrito")
    case .italic: return wrap(source, selection, marker: "_", placeholder: "itálico")
    case .strike: return wrap(source, selection, marker: "~~", placeholder: "riscado")
    case .code:
      // Code over several lines does not fit between backticks: it becomes a block.
      return source.slice(selection.start, selection.end).contains("\n")
        ? codeBlock(source, selection)
        : wrap(source, selection, marker: "`", placeholder: "código")
    case .link: return link(source, selection)
    case .codeBlock: return codeBlock(source, selection)
    case .heading, .bullet, .task, .quote, .ordered: return prefixLines(source, selection, action)
    }
  }

  /// Return inside a list opens the next item with the same marker (next number,
  /// unchecked box). Return on an empty item ends the list. nil outside a list.
  static func continueList(_ text: String, selection: TextSelection) -> TextEdit? {
    guard selection.start == selection.end else { return nil }
    let source = Source(text)
    let lineStart = source.lastNewline(before: selection.start) + 1
    let newline = source.nextNewline(from: selection.start)
    let lineEnd = newline ?? source.length
    let line = source.slice(lineStart, lineEnd)
    guard
      let match = line.wholeMatch(of: /(\s*)([-*+]|[0-9]+[.)])(\s+)(\[[ xX]\]\s+)?(.*)/)
    else { return nil }

    let indent = String(match.1)
    let marker = String(match.2)
    let space = String(match.3)
    let content = String(match.5)
    let prefixLength = line.utf16.count - content.utf16.count
    // Caret inside the marker: that edits the marker, it does not continue the item.
    if selection.start - lineStart < prefixLength { return nil }

    if content.trimmingCharacters(in: .whitespaces).isEmpty {
      return TextEdit(
        from: lineStart, to: lineEnd, insert: "", selection: TextSelection(start: lineStart, end: lineStart))
    }

    var nextMarker = marker
    if let ordered = marker.wholeMatch(of: /([0-9]+)([.)])/), let number = Int(ordered.1) {
      nextMarker = "\(number + 1)\(ordered.2)"
    }
    let insert = "\n\(indent)\(nextMarker)\(space)\(match.4 == nil ? "" : "[ ] ")"
    let caret = selection.start + insert.utf16.count
    return TextEdit(
      from: selection.start, to: selection.start, insert: insert, selection: TextSelection(start: caret, end: caret))
  }

  // MARK: - Actions

  /// Marks around the selection; an already marked selection is unmarked.
  private static func wrap(_ source: Source, _ sel: TextSelection, marker: String, placeholder: String) -> TextEdit {
    let m = marker.utf16.count
    let before = source.slice(sel.start - m, sel.start)
    let after = source.slice(sel.end, sel.end + m)

    if before == marker && after == marker {
      return TextEdit(
        from: sel.start - m, to: sel.end + m, insert: source.slice(sel.start, sel.end),
        selection: TextSelection(start: sel.start - m, end: sel.end - m))
    }

    let selected = source.slice(sel.start, sel.end)
    let inner = selected.isEmpty ? placeholder : selected
    return TextEdit(
      from: sel.start, to: sel.end, insert: "\(marker)\(inner)\(marker)",
      selection: TextSelection(start: sel.start + m, end: sel.start + m + inner.utf16.count))
  }

  private static func link(_ source: Source, _ sel: TextSelection) -> TextEdit {
    let selected = source.slice(sel.start, sel.end)
    // A selected address becomes the target and the label is left to write.
    if selected.wholeMatch(of: /https?:\/\/\S+/.ignoresCase()) != nil {
      let label = "texto"
      return TextEdit(
        from: sel.start, to: sel.end, insert: "[\(label)](\(selected))",
        selection: TextSelection(start: sel.start + 1, end: sel.start + 1 + label.utf16.count))
    }
    let label = selected.isEmpty ? "texto" : selected
    let url = "https://"
    let urlStart = sel.start + label.utf16.count + 3
    return TextEdit(
      from: sel.start, to: sel.end, insert: "[\(label)](\(url))",
      selection: TextSelection(start: urlStart, end: urlStart + url.utf16.count))
  }

  private static func codeBlock(_ source: Source, _ sel: TextSelection) -> TextEdit {
    let selected = source.slice(sel.start, sel.end)
    let inner = selected.isEmpty ? "código" : selected
    // The fence must start and end on lines of its own.
    let lead = sel.start > 0 && !source.isNewline(at: sel.start - 1) ? "\n" : ""
    let tail = sel.end < source.length && !source.isNewline(at: sel.end) ? "\n" : ""
    let open = "\(lead)```\n"
    let openLength = open.utf16.count
    return TextEdit(
      from: sel.start, to: sel.end, insert: "\(open)\(inner)\n```\(tail)",
      selection: TextSelection(start: sel.start + openLength, end: sel.start + openLength + inner.utf16.count))
  }

  /// A prefix on every line the selection touches; if all already have it, removes it.
  private static func prefixLines(_ source: Source, _ sel: TextSelection, _ action: MarkdownAction) -> TextEdit {
    let bounds = lineBounds(source, sel)
    let lines = source.slice(bounds.start, bounds.end).components(separatedBy: "\n")
    let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let remove = !filled.isEmpty && filled.allSatisfy { hasPrefix($0, action) }

    var counter = 0
    let next = lines.map { line -> String in
      if remove { return removingPrefix(line, action) }
      if line.trimmingCharacters(in: .whitespaces).isEmpty && lines.count > 1 { return line }
      counter += 1
      return (action == .ordered ? "\(counter). " : addedPrefix(action)) + line
    }
    let insert = next.joined(separator: "\n")

    // One line: the caret follows the text instead of jumping to the line start.
    if lines.count == 1 {
      let shift = insert.utf16.count - lines[0].utf16.count
      let clamp = { (position: Int) in max(bounds.start, position + shift) }
      return TextEdit(
        from: bounds.start, to: bounds.end, insert: insert,
        selection: TextSelection(start: clamp(sel.start), end: clamp(sel.end)))
    }
    return TextEdit(
      from: bounds.start, to: bounds.end, insert: insert,
      selection: TextSelection(start: bounds.start, end: bounds.start + insert.utf16.count))
  }

  private static func lineBounds(_ source: Source, _ sel: TextSelection) -> TextSelection {
    let start = source.lastNewline(before: sel.start) + 1
    // A selection ending right after a line break leaves the next line out, which
    // is what selecting whole lines with the mouse produces.
    let endAt = sel.end > sel.start && source.isNewline(at: sel.end - 1) ? sel.end - 1 : sel.end
    return TextSelection(start: start, end: source.nextNewline(from: endAt) ?? source.length)
  }

  private static func addedPrefix(_ action: MarkdownAction) -> String {
    switch action {
    case .heading: "## "
    case .bullet: "- "
    case .task: "- [ ] "
    case .quote: "> "
    default: ""
    }
  }

  private static func prefixMatch(_ line: String, _ action: MarkdownAction) -> Range<String.Index>? {
    switch action {
    case .heading: line.prefixMatch(of: /#{1,6}\s/)?.range
    // A task item is not a plain bullet.
    case .bullet: line.prefixMatch(of: /[-*+]\s(?!\[[ xX]\])/)?.range
    case .task: line.prefixMatch(of: /[-*+]\s\[[ xX]\]\s/)?.range
    case .quote: line.prefixMatch(of: />\s?/)?.range
    case .ordered: line.prefixMatch(of: /[0-9]+[.)]\s/)?.range
    default: nil
    }
  }

  private static func hasPrefix(_ line: String, _ action: MarkdownAction) -> Bool {
    prefixMatch(line, action) != nil
  }

  private static func removingPrefix(_ line: String, _ action: MarkdownAction) -> String {
    guard let range = prefixMatch(line, action) else { return line }
    var result = line
    result.removeSubrange(range)
    return result
  }
}

/// The text addressed in UTF-16 offsets, with JavaScript's clamping `slice`.
private struct Source {
  let text: NSString
  var length: Int { text.length }

  init(_ text: String) {
    self.text = text as NSString
  }

  func slice(_ start: Int, _ end: Int) -> String {
    let lower = min(max(0, start), length)
    let upper = min(max(lower, end), length)
    return text.substring(with: NSRange(location: lower, length: upper - lower))
  }

  func isNewline(at index: Int) -> Bool {
    index >= 0 && index < length && text.character(at: index) == 0x0A
  }

  /// Offset of the last line break before `position`, or -1.
  func lastNewline(before position: Int) -> Int {
    var index = min(position, length) - 1
    while index >= 0 {
      if text.character(at: index) == 0x0A { return index }
      index -= 1
    }
    return -1
  }

  /// Offset of the first line break at or after `position`.
  func nextNewline(from position: Int) -> Int? {
    var index = max(0, position)
    while index < length {
      if text.character(at: index) == 0x0A { return index }
      index += 1
    }
    return nil
  }
}
