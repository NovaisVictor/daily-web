import AppKit
import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The Slack module as a page or a window of its own (`components/SlackPanel.tsx`).
public struct SlackScreen: View {
  private let store: SlackStore

  public init(environment: AppEnvironment) {
    store = SlackStore.shared(in: environment)
  }

  public var body: some View {
    SlackModuleView(store: store, onOpenWindow: nil)
      .padding(24)
  }
}

/// The Slack panel of Início (`components/SlackPanel.tsx:71-93`, spec 011
/// FR-011-08), without a frame of its own: the host puts it on the panel
/// surface. Shares its store with `SlackScreen`.
public struct SlackPanel: View {
  private let store: SlackStore
  private let onOpenWindow: (() -> Void)?

  public init(environment: AppEnvironment) {
    self.init(environment: environment, onOpenWindow: nil)
  }

  /// With `onOpenWindow`, the header's "…" offers "Abrir em nova janela".
  public init(environment: AppEnvironment, onOpenWindow: (() -> Void)?) {
    self.onOpenWindow = onOpenWindow
    store = SlackStore.shared(in: environment)
  }

  public var body: some View {
    SlackModuleView(store: store, onOpenWindow: onOpenWindow)
  }
}

/// Mentions and direct messages, read-only; each one opens in Slack.
struct SlackModuleView: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  @Environment(\.isPrimaryWindow) private var isPrimaryWindow
  @Bindable var store: SlackStore
  /// The header's "Abrir em nova janela"; nil hides the menu.
  let onOpenWindow: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        SectionHeader("Slack") {
          if let onOpenWindow {
            IconMenu("mais ações do Slack", systemImage: "ellipsis") {
              Button("Abrir em nova janela", systemImage: "macwindow.badge.plus", action: onOpenWindow)
            }
          }
        }
        if !store.team.isEmpty {
          Text(store.team)
            .typeRole(.caption)
            .foregroundStyle(theme.inkDim)
        }
      }
      tabs
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task { revealPending() }
    .onChange(of: store.pendingItemID) { revealPending() }
    .onChange(of: store.panel?.data) { revealPending() }
  }

  /// In a narrow panel the tabs scroll sideways instead of squeezing their labels.
  private var tabs: some View {
    let pills = SegmentedPills(
      "listas do Slack",
      items: SlackTab.allCases.map { .init(id: $0, label: $0.label, count: store.count($0)) },
      selection: $store.tab
    )
    .fixedSize()
    return ViewThatFits(in: .horizontal) {
      pills
      ScrollView(.horizontal, showsIndicators: false) { pills }
    }
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
      // `flex-wrap` on the web: in a narrow panel the date drops to its own line.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          author
          channel
          Spacer(minLength: 8)
          date
        }
        FlowLayout(spacing: 8) {
          author
          channel
          date
        }
      }
      Text(message.text)
        .font(.daily(size: 14))
        .foregroundStyle(theme.inkMid)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private var author: some View {
    Text(message.author)
      .font(.daily(size: 14, weight: .medium))
      .foregroundStyle(theme.ink)
  }

  private var channel: some View {
    Text(message.channel)
      .typeRole(.caption)
      .foregroundStyle(theme.inkDim)
  }

  private var date: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      Text(SlackDates.relative(message.date, now: context.date))
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
    }
  }
}

#Preview("Slack") {
  SlackScreen(environment: .preview())
    .frame(width: 640, height: 480)
}

#Preview("Slack · 420pt") {
  SlackPanel(environment: .preview(), onOpenWindow: {})
    .padding(16)
    .glassSurface(.panel)
    .frame(width: 420, height: 480)
    .padding()
}

#Preview("Slack · 700pt") {
  SlackPanel(environment: .preview(), onOpenWindow: {})
    .padding(16)
    .glassSurface(.panel)
    .frame(width: 700, height: 480)
    .padding()
}
