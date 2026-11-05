import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The situation of an issue (`components/data/JiraStatus.tsx`): a glyph with the
/// tone, so the reading survives without colour.
struct JiraStatusLabel: View {
  @Environment(\.theme) private var theme
  let issue: JiraItem

  var body: some View {
    let (glyph, tone) = Self.style(issue.statusCategory)
    HStack(spacing: 6) {
      Text(glyph.rawValue).accessibilityHidden(true)
      Text(JiraFormat.normalizeStatus(issue.status))
    }
    .font(.daily(size: 12))
    .foregroundStyle(theme.color(for: tone))
    .lineLimit(1)
    .fixedSize()
  }

  static func style(_ category: JiraStatusCategory) -> (StatusGlyph, StatusTone) {
    switch category {
    case .indeterminate: (.moving, .info)
    case .done: (.live, .success)
    default: (.idle, .neutral)
    }
  }
}

/// Only the two highest priorities get a colour (`PRIORITY_TONE`).
struct JiraPriorityLabel: View {
  @Environment(\.theme) private var theme
  let issue: JiraItem

  var body: some View {
    if let priority = issue.priority {
      Text(priority.name)
        .font(.daily(size: 12))
        .foregroundStyle(color(priority.rank))
        .lineLimit(1)
        .fixedSize()
        .help("prioridade")
    }
  }

  private func color(_ rank: Int?) -> Color {
    switch rank {
    case 0: theme.danger
    case 1: theme.warning
    default: theme.inkDim
    }
  }
}

/// A small rounded label (`roleBadge`).
struct JiraRoleBadge: View {
  @Environment(\.theme) private var theme
  let text: String
  var tone: StatusTone = .neutral
  var bold = false

  var body: some View {
    Text(text)
      .font(.daily(size: 11, weight: bold ? .semibold : .regular))
      .foregroundStyle(tone == .neutral ? theme.inkDim : theme.color(for: tone))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(theme.tint(for: tone), in: .capsule)
      .overlay { Capsule().strokeBorder(theme.border(for: tone)) }
      .lineLimit(1)
      .fixedSize()
  }
}

/// The red flag of an impeded issue (`JiraFlagMark`), shown on path rows.
struct JiraFlagMark: View {
  @Environment(\.theme) private var theme

  var body: some View {
    Image(systemName: "flag.fill")
      .font(.system(size: 11))
      .foregroundStyle(theme.danger)
      .help("impedimento")
      .accessibilityLabel("impedimento")
  }
}

/// The pull requests citing an issue (`JiraPullLinks`).
struct JiraPullLinks: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let key: String
  let pulls: [PullRequestItem]

  var body: some View {
    if !pulls.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(pulls, id: \.url) { pull in
          Button {
            if let url = URL(string: pull.url) { openURL(url) }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "arrow.triangle.pull").accessibilityHidden(true)
              Text("\(pull.repo)#\(pull.number)").monospacedDigit().fixedSize()
              Text(pull.title).lineLimit(1).truncationMode(.tail)
            }
            .font(.daily(size: 12))
            .foregroundStyle(theme.inkDim)
          }
          .buttonStyle(.plain)
          .help(pull.url)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("PRs de \(key)")
    }
  }
}

/// The issue key, a link to Jira (`font-mono text-brand`).
struct JiraKeyLink: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let issue: JiraItem

  var body: some View {
    Button(issue.key) {
      if let url = URL(string: issue.url) { openURL(url) }
    }
    .buttonStyle(.plain)
    .font(.dailyMono(size: 13))
    .foregroundStyle(theme.brand)
    .fixedSize()
    .help("abrir \(issue.key) no Jira")
    .accessibilityLabel(issue.key)
    .accessibilityHint("abre no Jira")
  }
}

/// A group heading with its count (`groupLabel`).
struct JiraGroupHeading: View {
  @Environment(\.theme) private var theme
  let title: String
  let count: Int?

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
      if let count { Text("\(count)").monospacedDigit().fontWeight(.regular) }
    }
    .typeRole(.caption)
    .foregroundStyle(theme.inkDim)
    .accessibilityAddTraits(.isHeader)
    .padding(.bottom, 4)
  }
}

/// The removable badges of the active filters (`components/ui/ActiveFilters.tsx`).
struct JiraActiveFiltersRow: View {
  @Environment(\.theme) private var theme
  let filters: [JiraActiveFilter]
  let remove: (JiraActiveFilter.Kind) -> Void
  let clearAll: () -> Void

  var body: some View {
    if !filters.isEmpty {
      FlowLayout(spacing: 8) {
        ForEach(filters) { filter in
          HStack(spacing: 4) {
            Text(filter.label).typeRole(.caption).lineLimit(1)
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

/// A line of red text for a refusal, with "abrir no Jira" (`Refusal`).
struct JiraRefusal: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  let message: String?
  let issue: JiraItem

  var body: some View {
    if let message {
      HStack(spacing: 4) {
        Text(message).foregroundStyle(theme.danger)
        Text("·").foregroundStyle(theme.inkDim)
        Button {
          if let url = URL(string: issue.url) { openURL(url) }
        } label: {
          Label("abrir no Jira", systemImage: "arrow.up.right.square")
        }
        .linkButtonStyle()
      }
      .font(.daily(size: 12))
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityElement(children: .contain)
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

/// The order trigger (`JiraPanel.tsx:840-864`, JR-14): a 32pt rimmed circle that opens
/// the "Ordenar por" radio menu.
struct JiraSortMenu: View {
  @Binding var order: JiraOrder

  var body: some View {
    IconMenu("Ordenar: \(order.label)", systemImage: "arrow.up.arrow.down", variant: .outline) {
      Picker("Ordenar por", selection: $order) {
        ForEach(JiraOrder.allCases, id: \.self) { order in Text(order.label).tag(order) }
      }
      .pickerStyle(.inline)
    }
  }
}
