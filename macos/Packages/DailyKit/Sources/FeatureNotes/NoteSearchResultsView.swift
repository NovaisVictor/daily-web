import DailyDesign
import SwiftUI

/// Search hits with snippet and folder path (`components/notes/NoteSearchResults.tsx`).
struct NoteSearchResultsView: View {
  let results: [NoteSearchResult]
  let activeID: String?
  let onOpen: (String) -> Void

  @State private var selection: String?
  @FocusState private var focused: Bool
  @Environment(\.theme) private var theme

  var body: some View {
    if results.isEmpty {
      Text("Nenhuma nota encontrada.")
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityAddTraits(.updatesFrequently)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(results) { result in
              row(result)
                .id(result.id)
                .contentShape(.rect)
                .onTapGesture {
                  selection = result.id
                  focused = true
                }
                .accessibilityAction(.default) { selection = result.id }
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("resultados da busca")
        // The web's own active row in place of the system selection (NT-10); the
        // arrows still walk the hits and open each one, as the list did.
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
          guard press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]) else { return .ignored }
          selection = ListCursor.step(
            from: selection, in: results.map(\.id), by: press.key == .downArrow ? 1 : -1)
          return .handled
        }
        .onChange(of: selection) { _, id in
          guard let id else { return }
          proxy.scrollTo(id)
          onOpen(id)
        }
      }
      .onAppear { selection = activeID }
    }
  }

  /// `NoteSearchResults.tsx:31-46`: `px-2 py-1.5`, title in `text-sm`, snippet and path
  /// in `type-caption`; the keyboard cursor keeps a ring while the list has focus.
  private func row(_ result: NoteSearchResult) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(result.note.title.isEmpty ? "sem título" : result.note.title, systemImage: "doc.text")
        .font(.geist(14))
        .lineLimit(1)
      if !result.snippet.isEmpty {
        Text(result.snippet)
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
          .lineLimit(2)
      }
      Text(result.path.isEmpty ? "Sem pasta" : result.path.joined(separator: " / "))
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .activeRow(result.id == activeID)
    .clipShape(.rect(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(theme.brandEdge)
        .opacity(focused && selection == result.id ? 1 : 0)
        .allowsHitTesting(false)
    }
    .accessibilityElement(children: .combine)
  }
}
