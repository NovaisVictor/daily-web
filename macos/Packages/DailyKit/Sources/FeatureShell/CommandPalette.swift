import DailyDesign
import SwiftUI

/// One searchable palette action.
public struct PaletteCommand: Identifiable {
  public let id: String
  /// Group heading; groups show in the order they first appear in the list.
  public let group: String
  public let title: String
  /// SF Symbol name; nil for rows the web also shows without an icon.
  public let systemImage: String?
  /// Extra words that find the command without being shown.
  public let keywords: [String]
  public let action: () -> Void

  public init(
    id: String,
    group: String,
    title: String,
    systemImage: String? = nil,
    keywords: [String] = [],
    action: @escaping () -> Void
  ) {
    self.id = id
    self.group = group
    self.title = title
    self.systemImage = systemImage
    self.keywords = keywords
    self.action = action
  }
}

/// Commands under one heading, after filtering.
public struct PaletteGroup: Identifiable {
  public let title: String
  public let commands: [PaletteCommand]
  public var id: String { title }
}

/// Matching and keyboard movement for the palette, kept apart from the view so it can be tested.
public enum PaletteSearch {
  /// Groups the commands that match `query`, keeping the commands' order. Every word of
  /// the query must match, ignoring case and accents, either inside the group, title or
  /// keywords (the web prefixes each value with its group, so the group is searchable
  /// too) or as letters in order inside one of their words ("cfg" finds "Configuração").
  public static func groups(_ commands: [PaletteCommand], matching query: String) -> [PaletteGroup] {
    let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    var order: [String] = []
    var byGroup: [String: [PaletteCommand]] = [:]
    for command in commands where matches(command, tokens: tokens) {
      if byGroup[command.group] == nil { order.append(command.group) }
      byGroup[command.group, default: []].append(command)
    }
    return order.map { PaletteGroup(title: $0, commands: byGroup[$0, default: []]) }
  }

  /// The id after moving the highlight by `delta`, stopping at either end like cmdk does.
  public static func move(from current: String?, by delta: Int, in ids: [String]) -> String? {
    guard !ids.isEmpty else { return nil }
    guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
    return ids[min(max(index + delta, 0), ids.count - 1)]
  }

  static func normalize(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
  }

  private static func matches(_ command: PaletteCommand, tokens: [String]) -> Bool {
    let haystack = normalize(([command.group, command.title] + command.keywords).joined(separator: " "))
    let words = haystack.split(whereSeparator: \.isWhitespace)
    return tokens.allSatisfy { token in
      haystack.contains(token) || words.contains { isSubsequence(token, of: $0) }
    }
  }

  private static func isSubsequence(_ needle: String, of word: Substring) -> Bool {
    var remaining = needle[...]
    for character in word where remaining.first == character {
      remaining = remaining.dropFirst()
      if remaining.isEmpty { return true }
    }
    return remaining.isEmpty
  }
}

/// The ⌘K palette (`components/shell/CommandPalette.tsx`). Arrows move, Return runs,
/// Esc closes; running a command closes the palette first, then acts.
public struct CommandPalette: View {
  private let commands: [PaletteCommand]
  private let onClose: () -> Void

  @State private var query = ""
  @State private var highlighted: String?
  @FocusState private var isSearchFocused: Bool
  @Environment(\.theme) private var theme

  public init(commands: [PaletteCommand], onClose: @escaping () -> Void) {
    self.commands = commands
    self.onClose = onClose
  }

  private var groups: [PaletteGroup] { PaletteSearch.groups(commands, matching: query) }
  private var visibleIDs: [String] { groups.flatMap(\.commands).map(\.id) }

  /// The highlight falls back to the first row whenever filtering hides it.
  private var currentID: String? {
    if let highlighted, visibleIDs.contains(highlighted) { return highlighted }
    return visibleIDs.first
  }

  public var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider().overlay(theme.line)
      if groups.isEmpty {
        Text("Nada encontrado.")
          .font(.daily(size: 14))
          .foregroundStyle(theme.inkMid)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        results
      }
    }
    .frame(width: 560, height: 420)
    .background(theme.surface1)
    .onExitCommand(perform: onClose)
    .onAppear { isSearchFocused = true }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(theme.inkDim)
        .accessibilityHidden(true)
      TextField("Buscar", text: $query, prompt: Text("Buscar telas e ajustes…"))
        .textFieldStyle(.plain)
        .font(.daily(size: 14))
        .focused($isSearchFocused)
        .onSubmit(runHighlighted)
        .onKeyPress(.upArrow) {
          highlighted = PaletteSearch.move(from: currentID, by: -1, in: visibleIDs)
          return .handled
        }
        .onKeyPress(.downArrow) {
          highlighted = PaletteSearch.move(from: currentID, by: 1, in: visibleIDs)
          return .handled
        }
        .onKeyPress(.escape) {
          onClose()
          return .handled
        }
    }
    .padding(14)
  }

  private var results: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(groups) { group in
            // `[cmdk-group-heading]` (components/ui/command.tsx:121): `text-xs font-medium`.
            Text(group.title)
              .font(.daily(size: 12, weight: .medium))
              .foregroundStyle(theme.inkDim)
              .padding(.horizontal, 12)
              .padding(.top, 8)
              .padding(.bottom, 4)
              .accessibilityAddTraits(.isHeader)
            ForEach(group.commands) { command in
              row(command)
            }
          }
        }
        .padding(6)
      }
      .onChange(of: currentID) { _, id in
        guard let id else { return }
        proxy.scrollTo(id)
      }
    }
  }

  private func row(_ command: PaletteCommand) -> some View {
    let isHighlighted = command.id == currentID
    return Button {
      run(command)
    } label: {
      HStack(spacing: 10) {
        if let systemImage = command.systemImage {
          Image(systemName: systemImage)
            .frame(width: 16)
            .foregroundStyle(theme.inkMid)
            .accessibilityHidden(true)
        }
        Text(command.title).font(.daily(size: 14)).foregroundStyle(theme.ink)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .contentShape(.rect)
      .background(
        isHighlighted ? theme.brandTint : .clear,
        in: RoundedRectangle(cornerRadius: theme.radius / 2)
      )
    }
    .buttonStyle(.plain)
    .id(command.id)
    .onHover { hovering in
      if hovering { highlighted = command.id }
    }
    .accessibilityAddTraits(isHighlighted ? .isSelected : [])
  }

  private func runHighlighted() {
    guard let currentID, let command = commands.first(where: { $0.id == currentID }) else { return }
    run(command)
  }

  private func run(_ command: PaletteCommand) {
    onClose()
    command.action()
  }
}

#Preview("Paleta") {
  CommandPalette(commands: PreviewData.paletteCommands) {}
}

#Preview("Paleta vazia") {
  CommandPalette(commands: []) {}
}
