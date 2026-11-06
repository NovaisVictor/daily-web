import DailyDesign
import DailyModels
import SwiftUI

/// A task's checklist: tick, add, rename and delete subtasks. The list and
/// the board share it (`components/tasks/SubtaskList.tsx`).
struct SubtaskListView: View {
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var scheme
  let task: TodoTask
  let store: TasksStore
  @Binding var adding: Bool
  /// On a note the paper sets the colours.
  var ink: Color?

  @State private var newTitle = ""
  @State private var renaming: String?
  @State private var renameText = ""
  @State private var saving = false
  @FocusState private var focus: Field?

  private enum Field: Hashable {
    case add
    case rename(String)
    /// The title itself, so Tab reaches it and Return renames (A-2).
    case title(String)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: ink == nil ? 4 : 2) {
      ForEach(task.subtasks) { subtask in
        row(subtask)
      }
      if adding {
        HStack(spacing: 6) {
          TextField("nova subtarefa", text: $newTitle, prompt: Text("nova subtarefa"))
            .modifier(SubtaskFieldStyle(ink: ink))
            .focused($focus, equals: .add)
            .accessibilityLabel("nova subtarefa de \(task.title)")
            .singleLine($newTitle)
            .onSubmit(add)
            .onKeyPress(.escape) {
              finishAdding()
              return .handled
            }
            .onAppear { focus = .add }
          Button("Adicionar subtarefa", systemImage: "plus", action: add)
            .iconButtonStyle(size: .small, variant: .outline)
            .disabled(saving)
            .accessibilityLabel("Adicionar subtarefa")
        }
      } else if let ink {
        // `.postit-subtask-new`: the note's ink and wash.
        Button {
          adding = true
        } label: {
          Label("adicionar subtarefa", systemImage: "plus")
        }
        .buttonStyle(PaperButtonStyle(inks: PostitInks(ink: ink, scheme: scheme)))
        .font(.daily(size: 13))
        .padding(.leading, -7)
        .accessibilityLabel("adicionar subtarefa em \(task.title)")
      } else {
        Button {
          adding = true
        } label: {
          Label("adicionar subtarefa", systemImage: "plus").font(.daily(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.inkDim)
        .accessibilityLabel("adicionar subtarefa em \(task.title)")
      }
    }
  }

  @ViewBuilder
  private func row(_ subtask: SubTask) -> some View {
    HStack(spacing: 8) {
      Toggle(
        "concluir subtarefa \(subtask.title)",
        isOn: Binding(
          get: { subtask.completed },
          set: { _ in Task { await store.toggleSubtask(subtask, of: task) } })
      )
      .toggleStyle(.checkbox)
      // `.postit-check` takes the ink on a note; the list's checkbox the brand.
      .tint(ink.map { $0.opacity(0.78) } ?? theme.brand)
      .labelsHidden()
      .accessibilityLabel("concluir subtarefa \(subtask.title)")
      if renaming == subtask.id {
        TextField("título da subtarefa", text: $renameText)
          .modifier(SubtaskFieldStyle(ink: ink))
          .focused($focus, equals: .rename(subtask.id))
          .accessibilityLabel("renomear subtarefa \(subtask.title)")
          .singleLine($renameText)
          .onSubmit { commitRename(subtask) }
          .onKeyPress(.escape) {
            renaming = nil
            focus = .title(subtask.id)
            return .handled
          }
      } else {
        Text(subtask.title)
          .font(.daily(size: 13))
          .strikethrough(subtask.completed)
          .foregroundStyle(subtask.completed ? (ink ?? theme.inkDim).opacity(0.7) : (ink ?? theme.inkMid))
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(.rect)
          .focusable()
          .focused($focus, equals: .title(subtask.id))
          // An app-only addition: the web renames on double click alone.
          .onKeyPress(.return) {
            startRename(subtask)
            return .handled
          }
          .onTapGesture(count: 2) { startRename(subtask) }
          .contextMenu {
            Button("Renomear", systemImage: "pencil") { startRename(subtask) }
            Button("Apagar", systemImage: "trash", role: .destructive) {
              Task { await store.deleteSubtask(subtask, of: task) }
            }
          }
          .accessibilityAction(named: "Renomear") { startRename(subtask) }
          .help("Return ou clique duplo para renomear")
      }
      Button {
        Task { await store.deleteSubtask(subtask, of: task) }
      } label: {
        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
      }
      .buttonStyle(.plain)
      .foregroundStyle(ink ?? theme.inkDim)
      .accessibilityLabel("apagar subtarefa \(subtask.title)")
      .help("apagar subtarefa \(subtask.title)")
    }
  }

  private func startRename(_ subtask: SubTask) {
    renameText = subtask.title
    renaming = subtask.id
    focus = .rename(subtask.id)
  }

  private func commitRename(_ subtask: SubTask) {
    let title = renameText
    renaming = nil
    Task { await store.renameSubtask(subtask, of: task, to: title) }
  }

  private func add() {
    guard !saving, !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    saving = true
    let title = newTitle
    Task {
      let added = await store.addSubtask(to: task, title: title)
      saving = false
      if added {
        newTitle = ""
        finishAdding()
      }
    }
  }

  private func finishAdding() {
    adding = false
    newTitle = ""
  }
}

/// The app's input in the list; on a note, `.postit-input`: no box, an ink
/// underline over a lighter wash of the paper.
private struct SubtaskFieldStyle: ViewModifier {
  let ink: Color?

  func body(content: Content) -> some View {
    if let ink {
      content
        .textFieldStyle(.plain)
        .font(.daily(size: 13))
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(Color.white.opacity(0.2), in: .rect(cornerRadius: Radius.hairline))
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.35)).frame(height: 1) }
    } else {
      content.textFieldStyle(.roundedBorder)
    }
  }
}
