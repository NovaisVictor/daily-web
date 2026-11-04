import DailyCore
import DailyModels
import SwiftUI
import Testing

@testable import FeatureShell

@Suite struct PaletteSearchTests {
  private let commands: [PaletteCommand] = {
    let registry = ModuleRegistry(
      entries: [
        ModuleEntry(route: .today, title: "Hoje", systemImage: "sun.max", requiresModule: nil) { AnyView(EmptyView()) },
        ModuleEntry(route: .access, title: "Acesso dos agentes", systemImage: "key", requiresModule: nil) {
          AnyView(EmptyView())
        },
      ]
    )
    return ShellCommands.standard(
      sidebar: SidebarModel(registry: registry, enabled: []),
      navigate: { _ in }, setTheme: { _ in }, setDensity: { _ in }, setBackdrop: { _ in },
      profile: {}, changePassword: {}, changePhoto: {}, appearance: {}, signOut: {}
    )
  }()

  private func titles(_ query: String) -> [String] {
    PaletteSearch.groups(commands, matching: query).flatMap(\.commands).map(\.title)
  }

  @Test func emptyQueryKeepsTheWebGroupOrder() {
    let groups = PaletteSearch.groups(commands, matching: "  ")
    #expect(groups.map(\.title) == ["Ir para", "Tema", "Densidade", "Fundo", "Conta"])
    #expect(groups.first?.commands.map(\.title) == ["Hoje", "Acesso dos agentes"])
    #expect(
      groups.last?.commands.map(\.title) == ["Perfil", "Trocar senha", "Alterar foto de perfil", "Aparência", "Sair"]
    )
  }

  @Test func ignoresCaseAndAccents() {
    #expect(titles("APARENCIA") == ["Aparência"])
    #expect(titles("confortavel") == ["Densidade confortável"])
  }

  @Test func matchesKeywordsAndGroupNames() {
    // "Aparência" is found by its keyword; the Tema group by its heading.
    #expect(titles("densidade").contains("Aparência"))
    #expect(titles("ir para").count == 2)
  }

  @Test func everyWordMustMatch() {
    #expect(titles("tema escuro") == ["Tema escuro"])
    #expect(titles("fundo dracula") == ["Fundo Dracula"])
  }

  @Test func lettersInOrderInsideAWordMatch() {
    #expect(titles("wzt") == ["Fundo WezTerm"])
  }

  @Test func nothingMatchesReturnsNoGroups() {
    #expect(PaletteSearch.groups(commands, matching: "xyzzy").isEmpty)
  }

  @Test func filteredGroupsKeepTheirOrder() {
    #expect(PaletteSearch.groups(commands, matching: "fundo").map(\.title) == ["Fundo", "Conta"])
  }

  @Test func highlightMovesAndStopsAtTheEnds() {
    let ids = ["a", "b", "c"]
    #expect(PaletteSearch.move(from: "a", by: 1, in: ids) == "b")
    #expect(PaletteSearch.move(from: "c", by: 1, in: ids) == "c")
    #expect(PaletteSearch.move(from: "a", by: -1, in: ids) == "a")
    #expect(PaletteSearch.move(from: "gone", by: 1, in: ids) == "a")
    #expect(PaletteSearch.move(from: nil, by: 1, in: []) == nil)
  }

  @Test func commandsRunTheirClosures() {
    var chosen: [String] = []
    let built = ShellCommands.standard(
      sidebar: SidebarModel(registry: ModuleRegistry(entries: []), enabled: []),
      navigate: { chosen.append("\($0)") },
      setTheme: { chosen.append($0.rawValue) },
      setDensity: { chosen.append($0.rawValue) },
      setBackdrop: { chosen.append($0.rawValue) },
      profile: { chosen.append("profile") },
      changePassword: {}, changePhoto: {}, appearance: {},
      signOut: { chosen.append("signOut") }
    )
    for id in ["theme.dark", "density.compact", "backdrop.wezterm", "account.profile", "account.signOut"] {
      built.first { $0.id == id }?.action()
    }
    #expect(chosen == ["dark", "compact", "wezterm", "profile", "signOut"])
  }
}
