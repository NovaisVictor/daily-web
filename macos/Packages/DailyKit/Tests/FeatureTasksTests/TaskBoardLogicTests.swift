import DailyModels
import Testing

@testable import FeatureTasks

/// Ported from `tests/lib/taskBoard.test.ts`.
@Suite struct TaskBoardLogicTests {
  @Test func columnOfEachTask() {
    #expect(TaskBoard.column(of: makeTask()) == .todo)
    #expect(TaskBoard.column(of: makeTask(doing: true)) == .doing)
    #expect(TaskBoard.column(of: makeTask(completed: true, doing: true)) == .done)
  }

  @Test func groupsKeepingArrivalOrder() {
    let columns = TaskBoard.byColumn([
      makeTask("a"), makeTask("b", doing: true), makeTask("c", completed: true), makeTask("d"),
    ])
    #expect(columns[.todo]?.map(\.id) == ["a", "d"])
    #expect(columns[.doing]?.map(\.id) == ["b"])
    #expect(columns[.done]?.map(\.id) == ["c"])
  }

  @Test func neighbours() {
    #expect(BoardColumn.todo.neighbours.previous == nil)
    #expect(BoardColumn.todo.neighbours.next == .doing)
    #expect(BoardColumn.doing.neighbours.previous == .todo)
    #expect(BoardColumn.doing.neighbours.next == .done)
    #expect(BoardColumn.done.neighbours.next == nil)
  }

  @Test func movePlans() {
    #expect(TaskBoard.planMove(makeTask(doing: true), to: .done) == [.complete(true)])
    #expect(TaskBoard.planMove(makeTask(), to: .doing) == [.status(.doing)])
    #expect(TaskBoard.planMove(makeTask(doing: true), to: .todo) == [.status(.todo)])
    #expect(TaskBoard.planMove(makeTask(completed: true), to: .doing) == [.complete(false), .status(.doing)])
    #expect(TaskBoard.planMove(makeTask(doing: true), to: .doing).isEmpty)
  }

  @Test func tiltIsStableAndInRange() {
    let ids = ["a", "b", "AQMk+ADAw/abc==", "4f0c2a9e-1", String(repeating: "tarefa-muito-longa", count: 5)]
    for id in ids {
      #expect(TaskBoard.tilt(id) == TaskBoard.tilt(id))
      #expect((-2...2).contains(TaskBoard.tilt(id)))
    }
    #expect(Set(["1", "2", "3", "4", "5", "6"].map(TaskBoard.tilt)).count > 1)
  }

  @Test func paperFollowsPriorityAndChoice() {
    #expect(TaskBoard.paper(of: makeTask()) == .yellow)
    #expect(TaskBoard.paper(of: makeTask(priority: .high)) == .pink)
    #expect(TaskBoard.paper(of: makeTask(priority: .low)) == .blue)
    #expect(TaskBoard.paper(of: makeTask(completed: true, priority: .high)) == .green)
    #expect(TaskBoard.paper(of: makeTask(priority: .high, paper: .grey)) == .grey)
    #expect(TaskBoard.paper(of: makeTask(completed: true, paper: .white)) == .white)
  }

  @Test func automaticPinNeverClashesWithThePaperShown() {
    let ids = (0..<40).map { "t-\($0)" }
    for id in ids {
      #expect(TaskBoard.pin(of: makeTask(id)) != .yellow)
      #expect(TaskBoard.pin(of: makeTask(id, priority: .high)) != .red)
      #expect(TaskBoard.pin(of: makeTask(id, priority: .low)) != .blue)
      #expect(TaskBoard.pin(of: makeTask(id, completed: true)) != .green)
      #expect(TaskBoard.pin(of: makeTask(id, paper: .pink)) != .red)
      #expect(TaskBoard.pin(of: makeTask(id, paper: .white)) != .yellow)
    }
    #expect(Set(ids.map { TaskBoard.pin(of: makeTask($0)) }).count > 1)
    #expect(Set(ids.map { TaskBoard.pin(of: makeTask($0, paper: .blue)) }).contains(.yellow))
    #expect(TaskBoard.pin(of: makeTask(pin: .yellow)) == .yellow)
  }

  @Test func hashMatchesJavaScript() {
    // (((0*31+97)*31+98)) for "ab" = 3105; "a" = 97.
    #expect(TaskBoard.idHash("a") == 97)
    #expect(TaskBoard.idHash("ab") == 3105)
  }

  /// `idHash`, `noteTilt` and `noteCurls` of `lib/taskBoard.ts`, run in Node for
  /// the same ids (SC-014-1): short local ids, a Microsoft To Do id, a UUID,
  /// and one with non-ASCII letters (UTF-16 units, as `charCodeAt`).
  @Test(arguments: [
    ("t1", 3645, 1.7, true),
    ("t2", 3646, 1.8, true),
    ("t3", 3647, 1.9, true),
    ("t4", 3648, 2.0, false),
    ("t5", 3649, -2.0, false),
    ("t6", 3650, -1.9, false),
    ("a", 97, -0.5, false),
    ("AAMkAGI2TG93AAA=", 1_157_707_754, 0.0, false),
    ("task-42", 1_537_290_298, -0.7, true),
    ("ação", 3_118_866, 1.7, false),
    ("a1b2c3d4-e5f6-7890-abcd-ef1234567890", 1_891_949_682, -1.2, false),
  ])
  func tiltAndCurlMatchTheWeb(id: String, hash: Int, tilt: Double, curls: Bool) {
    #expect(TaskBoard.idHash(id) == hash)
    #expect(TaskBoard.tilt(id) == tilt)
    #expect(TaskBoard.curls(id) == curls)
  }

  @Test func aboutOneNoteInThreeCurls() {
    let curled = (0..<300).filter { TaskBoard.curls("task-\($0)") }.count
    #expect((70...130).contains(curled))
  }

  // MARK: Narrow board (`TaskBoard.tsx:393-421`)

  @Test func narrowBoardShowsOneColumnBehindTabs() {
    #expect(BoardTabs.usesTabs(width: 320))
    #expect(BoardTabs.usesTabs(width: 479))
    #expect(!BoardTabs.usesTabs(width: 480))
    #expect(BoardTabs.columns(width: 420, active: .doing) == [.doing])
    #expect(BoardTabs.columns(width: 420, active: .done) == [.done])
    #expect(BoardTabs.columns(width: 700, active: .doing) == [.todo, .doing, .done])
  }

  @Test func styleDescriptionsForAnnouncements() {
    #expect(NoteStylePatch(paper: .some(.pink)).description == "Papel rosa")
    #expect(NoteStylePatch(paper: .some(nil)).description == "Papel automático")
    #expect(NoteStylePatch(pin: .some(.green)).description == "Alfinete verde")
    #expect(NoteStylePatch(pin: .some(nil)).description == "Alfinete automático")
    #expect(NoteStylePatch(pinShape: .some(nil)).description == "Alfinete clássico")
  }
}
