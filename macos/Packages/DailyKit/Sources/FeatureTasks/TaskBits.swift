import DailyDesign
import DailyModels
import SwiftUI

/// The pin heads of `app/globals.css:1485-1504` (`--pin`). They are the same
/// in every theme, so they are literals here rather than `Theme` tokens.
enum PinPalette {
  static func color(_ pin: PinColor) -> Color {
    switch pin {
    case .red: Color(oklch: 0.6, 0.21, 27)
    case .blue: Color(oklch: 0.6, 0.17, 255)
    case .yellow: Color(oklch: 0.82, 0.16, 85)
    case .green: Color(oklch: 0.7, 0.19, 142)
    default: Color(oklch: 0.6, 0.21, 27)
    }
  }
}

/// The note's derived inks (`globals.css:1380-1403`). Only `--postit-ink` is
/// a `Theme` token; the others are drawn from it here.
// TODO: read `--postit-ink-mid` and `--postit-shadow` from Theme once DailyDesign has them.
struct PostitInks {
  let ink: Color
  let scheme: ColorScheme

  /// `--postit-ink-mid`: one step lighter than the ink on every paper.
  var mid: Color { ink.opacity(0.78) }
  /// `--postit-outline`: the ink at 55%.
  var outline: Color { ink.opacity(0.55) }
  /// `--postit-wash`: the hover wash of a control on the paper.
  var wash: Color { ink.opacity(0.1) }
  /// `--postit-drop`: `--postit-shadow` at 55% of its alpha, a hard shadow.
  var drop: Color {
    scheme == .dark ? Color.black.opacity(0.55 * 0.55) : Color(oklch: 0.3, 0.04, 70).opacity(0.3 * 0.55)
  }
  /// `.postit-due[data-overdue]`: the warning hue darkened to read on paper.
  var overdue: Color { Color(oklch: 0.42, 0.15, 88) }
}

/// Priority is a state: a glyph and a word beside the hue (`PRIORITY_TONE`).
struct PriorityPill: View {
  let priority: TaskPriority

  var body: some View {
    StatusPill(
      TaskText.priorityLabel(priority),
      glyph: priority == .high ? .alert : .idle,
      tone: priority == .high ? .warning : .neutral
    )
  }
}

/// The due date of a row. Late is said with a glyph and a word as well as the
/// warning hue, so it does not depend on telling colours apart.
struct DueLabel: View {
  @Environment(\.theme) private var theme
  let task: TodoTask
  let overdue: Bool
  var ink: Color?

  var body: some View {
    HStack(spacing: 4) {
      if overdue { Text(StatusGlyph.alert.rawValue).accessibilityHidden(true) }
      Text(TaskText.formatDue(task.due, time: task.time))
    }
    .font(.daily(size: 12, weight: overdue ? .medium : .regular).monospacedDigit())
    .foregroundStyle(overdue ? theme.warning : (ink ?? theme.inkDim))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      (overdue ? "atrasada, prazo " : "prazo ") + TaskText.formatDue(task.due, time: task.time))
  }
}

/// The removable badges of the active filters (`components/ui/ActiveFilters.tsx`).
struct ActiveFiltersRow: View {
  @Environment(\.theme) private var theme
  let filters: [ActiveFilter]
  let remove: (ActiveFilter.Kind) -> Void
  let clearAll: () -> Void

  var body: some View {
    if !filters.isEmpty {
      FlowLayout(spacing: 8) {
        ForEach(filters) { filter in
          HStack(spacing: 4) {
            Text(filter.label).typeRole(.caption)
            Button {
              remove(filter.id)
            } label: {
              Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.inkDim)
            .accessibilityLabel("remover filtro \(filter.label)")
          }
          .padding(.leading, 8)
          .padding(.trailing, 4)
          .padding(.vertical, 3)
          .background(theme.neutralTint, in: .capsule)
        }
        if filters.count > 1 {
          Button("Limpar tudo", systemImage: "xmark", action: clearAll)
            .pillButtonStyle(.ghost, size: .small)
        }
      }
    }
  }
}

extension View {
  /// `.draggable` only when there is something to drag.
  @ViewBuilder
  func draggableIfPresent<Payload: Transferable>(_ payload: Payload?) -> some View {
    if let payload {
      draggable(payload)
    } else {
      self
    }
  }
}
