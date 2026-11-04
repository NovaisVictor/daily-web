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

  static func symbol(_ shape: PinShape) -> String {
    switch shape {
    case .ball: "circle.fill"
    case .heart: "heart.fill"
    default: "pin.fill"
    }
  }
}

/// A pin head drawn with an SF Symbol in the pin's colour.
struct PushPinView: View {
  let color: PinColor
  let shape: PinShape
  var size: CGFloat = 14

  var body: some View {
    Image(systemName: PinPalette.symbol(shape))
      .font(.system(size: size))
      .foregroundStyle(PinPalette.color(color))
      .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
      .accessibilityHidden(true)
  }
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
    .font(.system(size: 12, weight: overdue ? .medium : .regular).monospacedDigit())
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
            .buttonStyle(.borderless)
            .controlSize(.small)
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
