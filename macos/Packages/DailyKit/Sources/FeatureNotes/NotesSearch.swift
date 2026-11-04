import DailyModels
import Foundation

/// One search hit (`lib/notesSearch.ts:27-36`).
struct NoteSearchResult: Equatable, Identifiable {
  enum Field: Equatable {
    case title
    case body
  }

  var note: Note
  /// The title wins over the body when both match.
  var field: Field
  /// Text around the match, with ellipses at cut ends.
  var snippet: String
  /// Folder path from the root inward; empty means "Sem pasta".
  var path: [String]

  var id: String { note.id }
}

/// Client-side search over title and body, as the web does it (`lib/notesSearch.ts`).
enum NotesSearch {
  /// Characters of context on each side of the match.
  static let snippetContext = 40
  /// `MAX_SEARCH_RESULTS`: a one-letter query would otherwise draw every note.
  static let maxResults = 50

  /// Accent- and case-insensitive form. Scalar by scalar on purpose: the snippet
  /// is cut from the original text at the offset found here, so the comparable
  /// form must keep the original's UTF-16 offsets.
  static func normalize(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
      let decomposed = String(scalar).decomposedStringWithCanonicalMapping
      var stripped = String.UnicodeScalarView()
      for part in decomposed.unicodeScalars where !(0x300...0x36F).contains(part.value) {
        stripped.append(part)
      }
      out += (stripped.isEmpty ? String(scalar) : String(stripped)).lowercased()
    }
    return out
  }

  /// - Parameter scopeIDs: restricts to these folders; `nil` inside the list is
  ///   "Sem pasta". A nil list searches everything.
  static func search(
    _ notes: [Note], folders: [NoteFolder], query: String, scopeIDs: [String?]? = nil
  ) -> [NoteSearchResult] {
    let needle = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !needle.isEmpty else { return [] }
    let needleLength = (needle as NSString).length

    var results: [NoteSearchResult] = []
    for note in notes {
      if let scopeIDs, !scopeIDs.contains(note.folderId) { continue }
      let inTitle = normalize(note.title).contains(needle)
      let found = (normalize(note.body) as NSString).range(of: needle, options: .literal)
      let inBody = found.location != NSNotFound
      guard inTitle || inBody else { continue }

      // Even on a title hit the snippet comes from the body: it tells apart
      // notes whose titles look alike.
      let snippet =
        inBody
        ? snippetAround(note.body, at: found.location, length: needleLength)
        : leading(collapseWhitespace(note.body), utf16Count: snippetContext * 2)
      results.append(
        NoteSearchResult(
          note: note,
          field: inTitle ? .title : .body,
          snippet: snippet,
          path: NotesTree.path(folders, to: note.folderId)))
    }

    // Title hits first, then the cut, so the cap never drops a title hit.
    let titles = results.filter { $0.field == .title }
    let bodies = results.filter { $0.field == .body }
    return Array((titles + bodies).prefix(maxResults))
  }

  private static func snippetAround(_ body: String, at index: Int, length: Int) -> String {
    let text = body as NSString
    let start = max(0, index - snippetContext)
    let end = min(text.length, index + length + snippetContext)
    let core = collapseWhitespace(text.substring(with: NSRange(location: start, length: end - start)))
    return "\(start > 0 ? "…" : "")\(core)\(end < text.length ? "…" : "")"
  }

  /// `slice(0, n)` in UTF-16 units, like the web.
  private static func leading(_ text: String, utf16Count count: Int) -> String {
    let value = text as NSString
    return value.substring(to: min(value.length, count))
  }

  private static func collapseWhitespace(_ text: String) -> String {
    text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
