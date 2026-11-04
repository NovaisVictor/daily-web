import DailyCore
import DailyDesign
import DailyModels
import SwiftUI

/// The bell of the main window toolbar (`components/NotificationsBell.tsx`):
/// the unread count on the icon and the "central de notificações" popover.
public struct NotificationsBell: View {
  @Environment(\.theme) private var theme
  @State private var store: NotificationsStore
  @State private var isOpen = false

  public init(environment: AppEnvironment) {
    _store = State(
      initialValue: NotificationsStore(
        client: environment.client,
        dashboard: environment.dashboard,
        alerts: environment.alerts,
        navigator: environment.navigator
      ))
  }

  public var body: some View {
    Button {
      isOpen.toggle()
    } label: {
      Image(systemName: store.unreadCount > 0 ? "bell.badge" : "bell")
    }
    // The number is information, not decoration: it shows as text on the
    // icon, not only as the bell's shape.
    .overlay(alignment: .topTrailing) {
      if store.unreadCount > 0 {
        Text("\(store.unreadCount)")
          .font(.system(size: 10, weight: .semibold).monospacedDigit())
          .foregroundStyle(theme.brandInk)
          .padding(.horizontal, 4)
          .frame(minWidth: 16, minHeight: 16)
          .background(theme.brand, in: .capsule)
          .offset(x: 6, y: -6)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .help("Notificações")
    .accessibilityLabel(NotificationsLogic.bellLabel(unread: store.unreadCount))
    .accessibilityValue(isOpen ? "aberta" : "fechada")
    .popover(isPresented: $isOpen, arrowEdge: .bottom) {
      NotificationCenterView(store: store) { isOpen = false }
    }
  }
}

/// The popover: filter, desktop alerts, "marcar todas" and the list.
struct NotificationCenterView: View {
  @Environment(\.theme) private var theme
  @Environment(\.openURL) private var openURL
  @Bindable var store: NotificationsStore
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      alertsRow
      if store.unreadCount > 0 { markAllRow }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if let error = store.panel.error { PanelError(error).padding(.vertical, 8) }
          if let error = store.error { PanelError(error).padding(.vertical, 8) }
          list
        }
        .padding(.horizontal, 16)
      }
    }
    .frame(width: 440)
    .frame(maxHeight: 600)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("central de notificações")
    .onExitCommand(perform: close)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text("Notificações")
        .typeRole(.subhead)
        .foregroundStyle(theme.ink)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 0)
      Menu {
        ForEach(NotificationsLogic.filterSources, id: \.self) { source in
          Toggle(
            NotificationsLogic.label(source),
            isOn: Binding(get: { store.isActive(source) }, set: { _ in store.toggle(source) }))
        }
      } label: {
        Label(
          store.activeSources.isEmpty ? "Filtrar" : "Filtrar (\(store.activeSources.count))",
          systemImage: store.activeSources.isEmpty
            ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .accessibilityLabel("Filtrar notificações")
    }
    .padding(16)
    .overlay(alignment: .bottom) { Divider().overlay(theme.line) }
  }

  @ViewBuilder private var alertsRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      if store.alertsDenied {
        Text("Avisos bloqueados no macOS — libere em Ajustes do Sistema → Notificações.")
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
          .fixedSize(horizontal: false, vertical: true)
        Button("Abrir Ajustes do Sistema") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            openURL(url)
          }
        }
        .buttonStyle(.link)
        .typeRole(.caption)
      }
      Chip("Avisar no computador", isOn: store.alertsEnabled, isDisabled: store.changingAlerts) {
        Task { await store.toggleAlerts() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .bottom) { Divider().overlay(theme.line) }
  }

  private var markAllRow: some View {
    HStack(spacing: 12) {
      Text(NotificationsLogic.unreadCaption(store.unreadCount))
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
      Spacer(minLength: 0)
      Button {
        Task { await store.markAllRead() }
      } label: {
        Image(systemName: "checkmark.circle")
          .symbolEffect(.pulse, isActive: store.markingAll)
      }
      .buttonStyle(.borderless)
      .disabled(store.markingAll)
      .help(store.markingAll ? "Marcando…" : "Marcar todas como lidas")
      .accessibilityLabel(store.markingAll ? "Marcando…" : "Marcar todas como lidas")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .overlay(alignment: .bottom) { Divider().overlay(theme.line) }
  }

  @ViewBuilder private var list: some View {
    if store.items.isEmpty {
      EmptyState(
        "Nenhuma notificação",
        description: "Quando chegar uma menção no Jira, um pull request ou um e-mail novo, aparece aqui.",
        systemImage: "bell.slash"
      )
      .padding(.vertical, 12)
    } else if store.visibleItems.isEmpty {
      Text("Nada com esse filtro.")
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .padding(.vertical, 32)
    } else {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
          NotificationRow(store: store, item: item, open: { open(item) })
          if index < store.visibleItems.count - 1 {
            Divider().overlay(theme.line)
          }
        }
      }
    }
  }

  private func open(_ item: NotificationItem) {
    switch store.destination(item) {
    case .browser(let url):
      openURL(url)
    case .app(let route, let itemID):
      store.navigate(route, itemID: itemID)
      close()
    case nil:
      break
    }
  }
}

private struct NotificationRow: View {
  @Environment(\.theme) private var theme
  @Bindable var store: NotificationsStore
  let item: NotificationItem
  let open: () -> Void

  private var mentionKey: String? { NotificationsLogic.mentionKey(item) }
  private var isWriting: Bool { store.reply?.id == item.id && store.reply?.stage == .writing }
  private var isPublished: Bool { store.reply?.id == item.id && store.reply?.stage == .published }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      title
      HStack(spacing: 8) {
        Text(NotificationsLogic.label(item.source))
          .typeRole(.caption)
          .tracking(0.8)
          .foregroundStyle(theme.inkDim)
        Spacer(minLength: 0)
        if mentionKey != nil {
          Button("Responder") { store.toggleReply(item) }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel("responder \(item.title)")
            .accessibilityValue(isWriting ? "aberto" : "fechado")
        }
        if !item.read {
          Button {
            Task { await store.markRead(item) }
          } label: {
            Image(systemName: "checkmark")
          }
          .buttonStyle(.borderless)
          .help("Marcar como lida")
          .accessibilityLabel("marcar \(item.title) como lida")
        }
      }
      if isWriting, store.reply != nil {
        ReplyForm(store: store)
      }
      if isPublished {
        Text("resposta publicada")
          .typeRole(.caption)
          .foregroundStyle(theme.inkMid)
      }
    }
    .padding(.vertical, 12)
    .contextMenu {
      if store.destination(item) != nil { Button("Abrir", action: open) }
      if !item.read {
        Button("Marcar como lida") { Task { await store.markRead(item) } }
      }
    }
  }

  @ViewBuilder private var title: some View {
    let label = Text(item.title)
      .typeRole(.body)
      .foregroundStyle(item.read ? theme.inkDim : theme.ink)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
    if store.destination(item) != nil {
      Button(action: open) { label }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityAddTraits(.isLink)
    } else {
      // The web's e-mail notice has no page; without the e-mail module there is nothing to open.
      label
    }
  }
}

/// `CommentForm`: a plain-text comment on the mentioned issue.
private struct ReplyForm: View {
  @Environment(\.theme) private var theme
  @Bindable var store: NotificationsStore
  @FocusState private var focused: Bool

  var body: some View {
    if let reply = store.reply {
      VStack(alignment: .leading, spacing: 8) {
        TextEditor(text: textBinding)
          .font(.system(size: 14))
          .frame(height: 88)
          .scrollContentBackground(.hidden)
          .padding(6)
          .background(theme.surface1, in: .rect(cornerRadius: Radius.small))
          .overlay {
            RoundedRectangle(cornerRadius: Radius.small)
              .strokeBorder(reply.problem == nil ? theme.lineStrong : theme.danger)
          }
          .disabled(reply.sending)
          .focused($focused)
          .accessibilityLabel("comentário em \(reply.issueKey)")
        if let problem = reply.problem {
          Text(problem)
            .typeRole(.caption)
            .foregroundStyle(theme.danger)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text("vai aparecer como seu comentário em \(reply.issueKey)")
          .typeRole(.caption)
          .foregroundStyle(theme.inkDim)
        HStack(spacing: 8) {
          Spacer(minLength: 0)
          Button("Cancelar") { store.cancelReply() }
            .disabled(reply.sending)
          Button(reply.sending ? "Comentando…" : "Comentar") {
            Task { await store.submitReply() }
          }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(!reply.ready)
        }
        .controlSize(.small)
      }
      .onAppear { focused = true }
    }
  }

  private var textBinding: Binding<String> {
    Binding(
      get: { store.reply?.text ?? "" },
      set: { store.reply?.text = $0 })
  }
}

#Preview {
  NotificationsBell(environment: .preview())
    .padding(40)
}
