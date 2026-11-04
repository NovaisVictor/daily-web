import DailyModels
import Testing

@testable import FeatureNotes

/// Cases from `tests/lib/notesSearch.test.ts`.
@Suite struct NotesSearchTests {
  private let folders = [
    folder("trabalho", name: "Trabalho"), folder("clientes", parent: "trabalho", name: "Clientes"),
  ]

  @Test func normalizeDropsAccentsAndCase() {
    #expect(NotesSearch.normalize("Sessão ÚNICA") == "sessao unica")
    let text = "ação café ñandu"
    #expect(NotesSearch.normalize(text).utf16.count == text.utf16.count)
  }

  @Test func emptyQueryFindsNothing() {
    #expect(NotesSearch.search([note("1", "Ideias", "texto")], folders: [], query: "   ").isEmpty)
  }

  @Test func findsByTitleAndByBody() {
    let byTitle = NotesSearch.search([note("1", "Reunião", "nada aqui")], folders: [], query: "reuniao")
    #expect(byTitle.map(\.id) == ["1"])
    #expect(byTitle.first?.field == .title)

    let byBody = NotesSearch.search([note("1", "Ideias", "combinamos a MIGRAÇÃO")], folders: [], query: "migracao")
    #expect(byBody.map(\.id) == ["1"])
    #expect(byBody.first?.field == .body)
  }

  @Test func ignoresCaseAndAccentsBothWays() {
    #expect(NotesSearch.search([note("1", "Férias", "sem nada")], folders: [], query: "FERIAS").count == 1)
    #expect(NotesSearch.search([note("2", "Ferias")], folders: [], query: "férias").count == 1)
  }

  @Test func snippetIsCutFromTheOriginalText() {
    let body =
      String(repeating: "a", count: 100) + " combinamos a migração para sexta " + String(repeating: "b", count: 100)
    let result = NotesSearch.search([note("1", "Ideias", body)], folders: [], query: "migração").first
    #expect(result?.snippet.contains("migração") == true)
    #expect(result?.snippet.hasPrefix("…") == true)
    #expect(result?.snippet.hasSuffix("…") == true)
  }

  @Test func showsTheFolderPath() {
    let notes = [note("1", "Contrato", folder: "clientes")]
    #expect(NotesSearch.search(notes, folders: folders, query: "contrato").first?.path == ["Trabalho", "Clientes"])
    #expect(NotesSearch.search([note("1", "Solta")], folders: folders, query: "solta").first?.path == [])
  }

  @Test func scopeLeavesOutsideNotesOut() {
    let notes = [note("1", "Contrato", folder: "clientes"), note("2", "Contrato")]
    let inside = NotesSearch.search(notes, folders: folders, query: "contrato", scopeIDs: ["trabalho", "clientes"])
    #expect(inside.map(\.id) == ["1"])
    let loose = NotesSearch.search(notes, folders: folders, query: "contrato", scopeIDs: [nil])
    #expect(loose.map(\.id) == ["2"])
  }

  @Test func titleHitsComeFirst() {
    let notes = [note("1", "Outra", "fala de contrato"), note("2", "Contrato", "nada")]
    #expect(NotesSearch.search(notes, folders: [], query: "contrato").map(\.id) == ["2", "1"])
  }
}
