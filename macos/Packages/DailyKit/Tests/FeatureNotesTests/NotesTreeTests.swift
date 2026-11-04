import DailyModels
import Testing

@testable import FeatureNotes

/// Cases from `tests/lib/notesTree.test.ts`.
@Suite struct NotesTreeTests {
  /// A chain of folders, each inside the previous one.
  private func chain(_ length: Int) -> [NoteFolder] {
    (0..<length).map { folder("n\($0)", parent: $0 == 0 ? nil : "n\($0 - 1)") }
  }

  @Test func nestsChildrenUnderTheirParent() {
    let tree = NotesTree.build([folder("a"), folder("b", parent: "a"), folder("c", parent: "b")])
    #expect(tree.map(\.id) == ["a"])
    #expect(tree[0].children.map(\.id) == ["b"])
    #expect(tree[0].children[0].children.map(\.id) == ["c"])
  }

  @Test func stampsTheDepthOfEachLevel() {
    let tree = NotesTree.build([folder("a"), folder("b", parent: "a"), folder("c", parent: "b")])
    #expect(tree[0].depth == 0)
    #expect(tree[0].children[0].depth == 1)
    #expect(tree[0].children[0].children[0].depth == 2)
  }

  @Test func sortsSiblingsByPosition() {
    let tree = NotesTree.build([folder("b", position: 2), folder("a", position: 1)])
    #expect(tree.map(\.id) == ["a", "b"])
  }

  @Test func orphanGoesToTheRootInsteadOfHiding() {
    let tree = NotesTree.build([folder("a"), folder("orfa", parent: "sumiu")])
    #expect(tree.map(\.id).sorted() == ["a", "orfa"])
  }

  @Test func storedCycleDoesNotLoop() {
    let tree = NotesTree.build([folder("a", parent: "b"), folder("b", parent: "a")])
    var ids: [String] = []
    func walk(_ nodes: [NoteFolderNode]) {
      for node in nodes {
        ids.append(node.id)
        walk(node.children)
      }
    }
    walk(tree)
    #expect(ids.sorted() == ["a", "b"])
  }

  @Test func descendantIDsIncludeEverythingInside() {
    let folders = [folder("a"), folder("b", parent: "a"), folder("c", parent: "b"), folder("d")]
    #expect(NotesTree.descendantIDs(folders, of: "a").sorted() == ["a", "b", "c"])
    #expect(NotesTree.descendantIDs([folder("a")], of: "a") == ["a"])
    #expect(NotesTree.descendantIDs([folder("a")], of: "de-outra-pessoa").isEmpty)
  }

  @Test func pathGoesFromTheRootInward() {
    #expect(NotesTree.path([folder("a"), folder("b", parent: "a")], to: "b") == ["a", "b"])
    #expect(NotesTree.path([folder("a")], to: nil).isEmpty)
  }

  @Test func refusesMovesThatBreakTheHierarchy() {
    #expect(NotesTree.refuseMove([folder("a"), folder("b", parent: "a")], id: "b", to: nil) == nil)
    #expect(NotesTree.refuseMove([folder("a")], id: "a", to: "a") == .cycle)
    let deep = [folder("a"), folder("b", parent: "a"), folder("c", parent: "b")]
    #expect(NotesTree.refuseMove(deep, id: "a", to: "c") == .cycle)
    #expect(NotesTree.refuseMove([folder("a")], id: "a", to: "sumiu") == .unknown)
  }

  @Test func refusesWhenTheBranchWouldPassTheMaximumDepth() {
    let full = chain(NotesTree.maxDepth)
    #expect(NotesTree.height(full, of: "n0") == NotesTree.maxDepth)
    #expect(NotesTree.depth(full, of: "n\(NotesTree.maxDepth - 1)") == NotesTree.maxDepth - 1)
    #expect(NotesTree.refuseMove(full + [folder("extra")], id: "extra", to: "n\(NotesTree.maxDepth - 1)") == .depth)
  }

  @Test func acceptsWhenTheBranchStillFits() {
    let shallow = chain(NotesTree.maxDepth - 1)
    #expect(NotesTree.refuseMove(shallow + [folder("extra")], id: "extra", to: "n\(NotesTree.maxDepth - 2)") == nil)
  }

  @Test func refusalsUseTheServerWords() {
    #expect(FolderMoveRefusal.cycle.message == "uma pasta não pode ir para dentro de si mesma")
    #expect(FolderMoveRefusal.depth.message == "a hierarquia de pastas ficou funda demais")
  }

  @Test func flattensVisibleRowsInDisplayOrder() {
    let folders = [folder("a", name: "Trabalho"), folder("b", parent: "a", name: "Clientes"), folder("vazia")]
    let notes = [note("n1", "Solta"), note("n2", "Contrato", folder: "b")]
    let closed = NoteTreeRow.flatten(notes: notes, folders: folders, expanded: [])
    #expect(closed.map(\.id) == ["__all__", "__none__", "folder:a", "folder:vazia"])

    let open = NoteTreeRow.flatten(notes: notes, folders: folders, expanded: ["__none__", "a", "b", "vazia"])
    #expect(
      open.map(\.id) == [
        "__all__", "__none__", "note:n1", "folder:a", "folder:b", "note:n2", "folder:vazia", "empty:vazia",
      ])
    #expect(open.first == .all(count: 2))
  }

  @Test func deletionPromptDescribesWhatHappens() {
    let folders = [folder("a", name: "Trabalho"), folder("b", parent: "a", name: "Clientes")]
    let empty = NotesTree.deletionPrompt(for: folders[1], folders: folders, notes: [])
    #expect(empty.title == "Apagar a pasta \"Clientes\"?")
    #expect(empty.message == "A pasta está vazia e será removida.")
    #expect(empty.confirmLabel == "Apagar")

    let full = NotesTree.deletionPrompt(
      for: folders[0], folders: folders, notes: [note("1", folder: "a"), note("2", folder: "b")])
    #expect(
      full.message
        == "A pasta tem 1 subpasta e 2 notas. Nenhuma nota é apagada: todas vão para \"Sem pasta\". "
        + "As subpastas são removidas junto.")
    #expect(full.confirmLabel == "Apagar e mover para Sem pasta")
  }
}
