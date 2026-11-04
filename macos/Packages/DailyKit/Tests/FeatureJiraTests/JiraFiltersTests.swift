import DailyModels
import Testing

@testable import FeatureJira

/// `tests/lib/jiraFilters.test.ts`. The URL cases are left out: the app keeps
/// the slice in memory, not in a URL.
@Suite struct JiraFiltersTests {
  static let obj = raw("TT-1", "Objective", 3)
  static let iniA = raw("TT-10", "Iniciativa", 2, "TT-1", summary: "Programa de fidelidade")
  static let iniB = raw("TT-20", "Iniciativa", 2, "TT-1", summary: "Pagamentos")
  static let epicA = raw("TT-11", "Epic", 1, "TT-10", summary: "Pontos por aposta")
  static let epicB = raw("TT-21", "Epic", 1, "TT-20", summary: "Pix")
  static let storyA1 = raw("TT-111", "História", 0, "TT-11", summary: "Tela de saldo")
  static let storyA2 = raw(
    "TT-112", "História", 0, "TT-11", summary: "API de extrato", status: "Backlog", category: .new)
  static let subA1 = raw("TT-1111", "Subtarefa", -1, "TT-111", summary: "Ajustar layout")
  static let storyB = raw("TT-211", "História", 0, "TT-21", summary: "QR code")

  static let all = [obj, iniA, iniB, epicA, epicB, storyA1, storyA2, subA1, storyB]
  static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
  static let mine = [storyA1, storyA2, subA1, storyB, epicB]

  @Test func modeButtonsNameTheirModeAsTheWeb() {
    #expect(JiraFilterMode.include.accessibilityLabel(for: "Status") == "modo é igual a para Status")
    #expect(JiraFilterMode.exclude.accessibilityLabel(for: "Status") == "modo não é igual a para Status")
    #expect(JiraFilterMode.include.title == "É igual a (=)")
    #expect(JiraFilterMode.exclude.title == "Não é igual a (≠)")
  }

  func keys(_ change: (inout JiraFilterState) -> Void) -> [String] {
    var filters = JiraFilterState()
    change(&filters)
    return Self.mine.filter { JiraFilters.matches($0, filters, byKey: Self.byKey) }.map(\.key)
  }

  // MARK: tierOf

  @Test func tierComesFromTheLevelNotTheTypeName() {
    #expect(JiraTier.of(Self.iniA) == .initiative)
    #expect(JiraTier.of(Self.epicA) == .epic)
    #expect(JiraTier.of(Self.storyA1) == .story)
    #expect(JiraTier.of(raw("TT-9", "Trilha", 2)) == .initiative)
    #expect(JiraTier.of(raw("TT-8", "Bug", 0)) == .story)
  }

  @Test func objectiveSubtaskAndUnknownLevelHaveNoTier() {
    var noLevel = Self.storyA1
    noLevel.hierarchyLevel = nil
    #expect(JiraTier.of(Self.obj) == nil)
    #expect(JiraTier.of(Self.subA1) == nil)
    #expect(JiraTier.of(noLevel) == nil)
  }

  // MARK: lineageOf

  @Test func lineageClimbsToTheKnownTop() {
    #expect(JiraFilters.lineage(of: Self.subA1, in: Self.byKey).map(\.key) == ["TT-111", "TT-11", "TT-10", "TT-1"])
  }

  @Test func lineageStopsAtAParentPointingBack() {
    let a = raw("X-1", "Epic", 1, "X-2")
    let b = raw("X-2", "Epic", 1, "X-1")
    #expect(JiraFilters.lineage(of: a, in: ["X-1": a, "X-2": b]).map(\.key) == ["X-2"])
  }

  // MARK: matchesJiraFilters

  @Test func withoutFiltersEverythingPasses() {
    #expect(keys { _ in } == Self.mine.map(\.key))
  }

  @Test func statusIgnoresCase() {
    #expect(keys { $0.status = JiraFilterGroup(["backlog"]) } == ["TT-112"])
  }

  @Test func severalStatusesAreAnOr() {
    #expect(keys { $0.status = JiraFilterGroup(["Backlog", "Em Andamento"]) } == Self.mine.map(\.key))
  }

  @Test func statusExclusion() {
    #expect(
      keys { $0.status = JiraFilterGroup(["Backlog"], mode: .exclude) } == ["TT-111", "TT-1111", "TT-211", "TT-21"])
  }

  @Test func tier() {
    #expect(keys { $0.tier = JiraFilterGroup(["story"]) } == ["TT-111", "TT-112", "TT-211"])
    #expect(keys { $0.tier = JiraFilterGroup(["epic"]) } == ["TT-21"])
    #expect(keys { $0.tier = JiraFilterGroup(["story", "epic"]) } == ["TT-111", "TT-112", "TT-211", "TT-21"])
  }

  @Test func tierExclusion() {
    #expect(keys { $0.tier = JiraFilterGroup(["story"], mode: .exclude) } == ["TT-1111", "TT-21"])
  }

  @Test func anInitiativeBringsEverythingUnderIt() {
    #expect(keys { $0.initiative = JiraFilterGroup(["TT-10"]) } == ["TT-111", "TT-112", "TT-1111"])
  }

  @Test func severalInitiatives() {
    #expect(
      keys { $0.initiative = JiraFilterGroup(["TT-10", "TT-20"]) } == [
        "TT-111", "TT-112", "TT-1111", "TT-211", "TT-21",
      ])
  }

  @Test func excludingAnInitiativeRemovesItsTree() {
    #expect(keys { $0.initiative = JiraFilterGroup(["TT-10"], mode: .exclude) } == ["TT-211", "TT-21"])
  }

  @Test func anEpicIncludesItselfWhenInTheList() {
    #expect(keys { $0.epic = JiraFilterGroup(["TT-21"]) } == ["TT-211", "TT-21"])
  }

  @Test func excludingAnEpicRemovesItAndItsChildren() {
    #expect(keys { $0.epic = JiraFilterGroup(["TT-21"], mode: .exclude) } == ["TT-111", "TT-112", "TT-1111"])
  }

  @Test func aStoryBringsItsSubtasks() {
    #expect(keys { $0.story = JiraFilterGroup(["TT-111"]) } == ["TT-111", "TT-1111"])
  }

  @Test func excludingAStoryRemovesItsSubtasks() {
    #expect(keys { $0.story = JiraFilterGroup(["TT-111"], mode: .exclude) } == ["TT-112", "TT-211", "TT-21"])
  }

  @Test func hierarchyFiltersAddUp() {
    #expect(
      keys {
        $0.initiative = JiraFilterGroup(["TT-10"])
        $0.epic = JiraFilterGroup(["TT-21"])
      } == [])
    #expect(
      keys {
        $0.initiative = JiraFilterGroup(["TT-10"])
        $0.tier = JiraFilterGroup(["story"])
        $0.status = JiraFilterGroup(["Em Andamento"])
      } == ["TT-111"])
  }

  @Test func searchFindsByAnAncestorsTitle() {
    #expect(keys { $0.query = "fidelidade" } == ["TT-111", "TT-112", "TT-1111"])
  }

  @Test func searchFindsByKeyAndTitleWithoutAccents() {
    #expect(keys { $0.query = "tt-211" } == ["TT-211"])
    #expect(keys { $0.query = "qr CODE" } == ["TT-211"])
    #expect(JiraText.matches(["Revisão"], query: "revisao"))
  }

  // MARK: jiraFilterOptions

  @Test func statusOptionsDoNotRepeatByCase() {
    var other = Self.storyB
    other.status = "em andamento"
    let options = JiraFilters.options([Self.storyA1, Self.storyA2, other], byKey: Self.byKey, filters: .empty)
    #expect(options.statuses == ["Backlog", "Em Andamento"])
  }

  @Test func offersInitiativesAndEpicsAboveTheList() {
    let options = JiraFilters.options(Self.mine, byKey: Self.byKey, filters: .empty)
    #expect(options.initiatives.map(\.key) == ["TT-20", "TT-10"])
    #expect(options.epics.map(\.key) == ["TT-21", "TT-11"])
  }

  @Test func cascadesFromTheChosenInitiative() {
    var filters = JiraFilterState()
    filters.initiative = JiraFilterGroup(["TT-10"])
    let options = JiraFilters.options(Self.mine, byKey: Self.byKey, filters: filters)
    #expect(options.epics.map(\.key) == ["TT-11"])
    #expect(options.stories.map(\.key) == ["TT-112", "TT-111"])
  }

  @Test func cascadesWithSeveralInitiatives() {
    var filters = JiraFilterState()
    filters.initiative = JiraFilterGroup(["TT-10", "TT-20"])
    let options = JiraFilters.options(Self.mine, byKey: Self.byKey, filters: filters)
    #expect(options.epics.map(\.key) == ["TT-21", "TT-11"])
    #expect(options.stories.map(\.key) == ["TT-112", "TT-211", "TT-111"])
  }

  @Test func cascadesFromTheChosenEpic() {
    var filters = JiraFilterState()
    filters.epic = JiraFilterGroup(["TT-21"])
    #expect(JiraFilters.options(Self.mine, byKey: Self.byKey, filters: filters).stories.map(\.key) == ["TT-211"])
  }

  @Test func doesNotOfferAnInitiativeWithNothingUnderIt() {
    let options = JiraFilters.options([Self.storyA1], byKey: Self.byKey, filters: .empty)
    #expect(options.initiatives.map(\.key) == ["TT-10"])
  }

  // MARK: State helpers

  @Test func isActiveOnlyWithARealFilter() {
    var filters = JiraFilterState()
    #expect(!filters.isActive)
    filters.query = "   "
    #expect(!filters.isActive)
    filters.tier = JiraFilterGroup(["epic"])
    #expect(filters.isActive)
    filters = JiraFilterState()
    filters.status = JiraFilterGroup(["Backlog"], mode: .exclude)
    #expect(filters.isActive)
  }

  @Test func clearingAnUpperTierFreesTheOnesBelow() {
    var filters = JiraFilterState()
    filters.initiative = JiraFilterGroup(["TT-10"])
    filters.epic = JiraFilterGroup(["TT-11"])
    filters.story = JiraFilterGroup(["TT-111"])
    filters.status = JiraFilterGroup(["Backlog"])
    filters.clear(.initiative)
    #expect(filters.epic.values.isEmpty && filters.story.values.isEmpty)
    #expect(filters.status.values == ["Backlog"])
  }

  @Test func switchingSubjectFreesBelowButAddingKeepsIt() {
    var filters = JiraFilterState()
    filters.initiative = JiraFilterGroup(["TT-10"])
    filters.epic = JiraFilterGroup(["TT-11"])
    filters.change(.initiative, to: JiraFilterGroup(["TT-10", "TT-20"]))
    #expect(filters.epic.values == ["TT-11"])
    filters.change(.initiative, to: JiraFilterGroup(["TT-10", "TT-20"], mode: .exclude))
    #expect(filters.epic.values == ["TT-11"])
    filters.change(.initiative, to: JiraFilterGroup(["TT-30"]))
    #expect(filters.epic.values.isEmpty)
  }

  @Test func activeFilterLabels() {
    var filters = JiraFilterState()
    filters.query = " saldo "
    filters.status = JiraFilterGroup(["Backlog", "Code Review"])
    filters.tier = JiraFilterGroup(["story", "epic"], mode: .exclude)
    filters.epic = JiraFilterGroup(["TT-11"])
    let labels = JiraFilters.active(filters) { "\($0) Pontos" }.map(\.label)
    #expect(
      labels == ["Busca: saldo", "Status: Backlog, Code Review", "Tipo ≠ Histórias, Épicos", "Épico: TT-11 Pontos"])
  }
}
