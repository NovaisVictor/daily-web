import AppKit
import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The Slack module (`components/SlackPanel.tsx`): mentions and direct
/// messages, read-only; each one opens in Slack.
public struct SlackScreen: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  @State private var store: SlackStore

  public init(environment: AppEnvironment) {
    _store = State(initialValue: SlackStore(dashboard: environment.dashboard, navigator: environment.navigator))
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        SectionHeader("Slack")
        if !store.team.isEmpty {
          Text(store.team)
            .typeRole(.caption)
            .foregroundStyle(theme.inkDim)
        }
      }
      Picker("listas do Slack", selection: $store.tab) {
        ForEach(SlackTab.allCases) { tab in
          Text("\(tab.label) \(store.count(tab))").tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityLabel("listas do Slack")
      .fixedSize()
      content
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder private var content: some View {
    if let error = store.error {
      PanelError(error)
    }
    if store.isLoading {
      LoadingState()
    } else if store.showsEmpty {
      EmptyState(store.tab.emptyText)
    }
    if !store.items.isEmpty {
      messageList
    } else {
      Spacer(minLength: 0)
    }
  }

  private var messageList: some View {
    ScrollViewReader { proxy in
      List(selection: $store.selection) {
        ForEach(store.items) { message in
          SlackMessageRow(message: message)
            .tag(message.id)
            .id(message.id)
        }
      }
      .listStyle(.inset)
      .scrollContentBackground(.hidden)
      .contextMenu(forSelectionType: String.self) { ids in
        if let message = message(ids), let url = SlackStore.link(message) {
          Button("Abrir no Slack") { openURL(url) }
          Button("Copiar link") { copy(url) }
        }
      } primaryAction: { ids in
        if let message = message(ids), let url = SlackStore.link(message) { openURL(url) }
      }
      .onAppear {
        if let id = store.revealPending() { proxy.scrollTo(id, anchor: .center) }
      }
    }
  }

  private func message(_ ids: Set<String>) -> SlackMessage? {
    guard let id = ids.first else { return nil }
    return store.items.first { $0.id == id }
  }

  private func copy(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
  }
}

/// `MessageRow`: author, channel, relative date and the text.
private struct SlackMessageRow: View {
  @Environment(\.theme) private var theme
  let message: SlackMessage

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(message.author)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(theme.ink)
        Text(message.channel)
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
        Spacer(minLength: 8)
        TimelineView(.periodic(from: .now, by: 60)) { context in
          Text(SlackDates.relative(message.date, now: context.date))
            .typeRole(.caption)
            .foregroundStyle(theme.inkDim)
        }
      }
      Text(message.text)
        .font(.system(size: 14))
        .foregroundStyle(theme.inkMid)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
    .accessibilityHint(SlackStore.link(message) == nil ? "" : "abre no Slack")
  }
}

#Preview {
  SlackScreen(environment: .preview())
    .frame(width: 640, height: 480)
}
