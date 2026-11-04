import DailyCore
import DailyModels
import Foundation

/// Sample tasks for previews. Titles are made up.
enum TasksPreviewData {
  static var state: DashboardState {
    var state = PreviewFixtures.dashboard
    let today = TaskGrouping.localISO(Date())
    state.tasks = PanelResult(
      data: [
        task(
          "t1", "Revisar proposta", due: today, priority: .high,
          subtasks: [
            SubTask(id: "s1", title: "Ler anexos", completed: true),
            SubTask(id: "s2", title: "Responder comentários", completed: false),
          ]),
        task("t2", "Preparar a daily", due: TaskGrouping.addDays(today, -1)),
        task("t3", "Atualizar documentação", due: TaskGrouping.addDays(today, 3), doing: true, paper: .blue),
        task("t4", "Pagar conta", due: TaskGrouping.addDays(today, 10), recur: "monthly"),
        task("t5", "Organizar arquivos", priority: .low),
        task("t6", "Enviar relatório", due: TaskGrouping.addDays(today, -2), completed: true),
      ],
      error: nil)
    state.tasksView = .board
    return state
  }

  private static func task(
    _ id: String,
    _ title: String,
    due: String = "",
    priority: TaskPriority = .normal,
    recur: String = "",
    subtasks: [SubTask] = [],
    doing: Bool = false,
    completed: Bool = false,
    paper: NotePaper? = nil
  ) -> TodoTask {
    TodoTask(
      id: id, title: title, completed: completed, due: due, priority: priority, time: "", recur: recur, notes: "",
      subtasks: subtasks, doing: doing, paper: paper, pin: nil, pinShape: nil)
  }
}
