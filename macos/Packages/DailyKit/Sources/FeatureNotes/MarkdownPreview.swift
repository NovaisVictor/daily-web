import DailyDesign
import SwiftUI
import Textual

/// The note read as Markdown (`components/MarkdownView.tsx`). Foundation's parser
/// never turns raw HTML into markup, and links leave the app for the browser.
struct MarkdownPreview: View {
  let source: String
  @Environment(\.theme) private var theme

  var body: some View {
    StructuredText(markdown: source)
      .textual.structuredTextStyle(.gitHub)
      .textual.textSelection(.enabled)
      .textual.imageAttachmentLoader(.image())
      .foregroundStyle(theme.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
      .environment(\.openURL, OpenURLAction(handler: Self.open))
  }

  /// Only web and mail links open, in the default apps. A `file:` or custom-scheme
  /// link inside a note could launch anything, which the web's URL filter also
  /// refuses (`MarkdownView.tsx:8-12`).
  static func open(_ url: URL) -> OpenURLAction.Result {
    guard isAllowed(url) else { return .discarded }
    return .systemAction(url)
  }

  static func isAllowed(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    return ["http", "https", "mailto"].contains(scheme)
  }
}
