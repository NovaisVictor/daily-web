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
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow

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
      SegmentedPills(
        "listas do Slack",
        items: SlackTab.allCases.map { .init(id: $0, label: $0.label, count: store.count($0)) },
        selection: $store.tab
      )
      .fixedSize()
      content
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task { revealPending() }
    .onChange(of: store.pendingItemID) { revealPending() }
    .onChange(of: store.panel?.data) { revealPending() }
  }

  /// Only the main window takes the request; it is the one the navigator moved.
  private func revealPending() {
    guard isPrimaryWindow else { return }
    store.revealPending()
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
      ScrollView {
        let items = store.items
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, message in
            ListRow(index: index, isLast: index == items.count - 1, isActive: store.selection == message.id) {
              row(message)
            }
            .id(message.id)
          }
        }
      }
      .onAppear { scrollToTarget(proxy) }
      .onChange(of: store.scrollTarget) { scrollToTarget(proxy) }
    }
  }

  private func scrollToTarget(_ proxy: ScrollViewProxy) {
    guard let id = store.scrollTarget else { return }
    proxy.scrollTo(id, anchor: .center)
    store.scrollTarget = nil
  }

  /// The web row is a link to Slack (`SlackPanel.tsx:35-42`); one without a link is text.
  @ViewBuilder
  private func row(_ message: SlackMessage) -> some View {
    if let url = SlackStore.link(message) {
      Button {
        store.selection = message.id
        openURL(url)
      } label: {
        SlackMessageRow(message: message).contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityHint("abre no Slack")
      .contextMenu {
        Button("Abrir no Slack") { openURL(url) }
        Button("Copiar link") { copy(url) }
      }
    } else {
      SlackMessageRow(message: message)
    }
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
          .font(.daily(size: 14, weight: .medium))
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
        .font(.daily(size: 14))
        .foregroundStyle(theme.inkMid)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  SlackScreen(environment: .preview())
    .frame(width: 640, height: 480)
}
