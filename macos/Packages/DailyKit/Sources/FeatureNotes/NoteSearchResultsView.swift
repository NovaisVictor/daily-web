import DailyDesign
import SwiftUI

/// Search hits with snippet and folder path (`components/notes/NoteSearchResults.tsx`).
struct NoteSearchResultsView: View {
  let results: [NoteSearchResult]
  let activeID: String?
  let onOpen: (String) -> Void

  @State private var selection: String?
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
      List(results, selection: $selection) { result in
        VStack(alignment: .leading, spacing: 2) {
          Label(result.note.title.isEmpty ? "sem título" : result.note.title, systemImage: "doc.text")
            .lineLimit(1)
            .foregroundStyle(result.id == activeID ? theme.ink : theme.inkMid)
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
        .padding(.vertical, 2)
        .tag(result.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(result.id == activeID ? .isSelected : [])
      }
      .listStyle(.sidebar)
      .accessibilityLabel("resultados da busca")
      .onChange(of: selection) { _, id in
        if let id { onOpen(id) }
      }
      .onAppear { selection = activeID }
    }
  }
}
