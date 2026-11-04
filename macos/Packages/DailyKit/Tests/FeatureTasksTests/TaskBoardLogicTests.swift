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

  @Test func styleDescriptionsForAnnouncements() {
    #expect(NoteStylePatch(paper: .some(.pink)).description == "Papel rosa")
    #expect(NoteStylePatch(paper: .some(nil)).description == "Papel automático")
    #expect(NoteStylePatch(pin: .some(.green)).description == "Alfinete verde")
    #expect(NoteStylePatch(pin: .some(nil)).description == "Alfinete automático")
    #expect(NoteStylePatch(pinShape: .some(nil)).description == "Alfinete clássico")
  }
}
