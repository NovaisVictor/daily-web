import AppKit
import DailyDesign
import DailyModels
import SwiftUI

/// The conversations, grouped as chosen. The whole list takes keyboard focus:
/// arrows walk, ⇧ extends, Space toggles, ⌘A takes everything, E deletes,
/// M moves and Esc clears (`aoTeclar` in `EmailPanel.tsx`).
struct EmailConversationList: View {
  @Environment(\.theme) private var theme
  @Environment(\.emailPresenter) private var presenter
  let store: EmailStore
  let listing: EmailListing
  @FocusState private var focused: Bool

  var body: some View {
    let stack = DragStackLookup(store: store, order: listing.order)
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(listing.groups) { group in
            if store.filters.groupBy != .none {
              EmailGroupHeader(store: store, group: group)
            }
            ForEach(Array(group.threads.enumerated()), id: \.element.id) { index, thread in
              let placement = stack.placement(of: thread.id)
              // The cursor ring stays without focus (`cursorAqui`, EM-9): it is
              // where the arrows resume and what the batch menu acts on.
              EmailThreadRow(
                store: store, thread: thread, group: group, index: index,
                isCursor: store.selection.cursor == thread.id, stack: placement
              )
              .id(thread.id)
              .zIndex(placement?.zIndex ?? 0)
              .simultaneousGesture(TapGesture().onEnded { focused = true })
            }
          }
        }
      }
      .focusable()
      .focused($focused)
      .focusEffectDisabled()
      .overlay {
        RoundedRectangle(cornerRadius: Radius.small)
          .strokeBorder(theme.brand.opacity(0.5), lineWidth: 2)
          .opacity(focused ? 1 : 0)
          .allowsHitTesting(false)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("conversas")
      .onKeyPress(phases: .down) { press in handle(press) }
      .onCommand(#selector(NSResponder.selectAll(_:))) { store.select(.all) }
      .onChange(of: store.selection.cursor) { _, cursor in
        guard let cursor else { return }
        proxy.scrollTo(cursor)
      }
      .onDragSessionUpdated { session in
        if case .ended = session.phase { store.endDrag() }
      }
    }
  }

  private func handle(_ press: KeyPress) -> KeyPress.Result {
    let plain = press.modifiers.isDisjoint(with: [.command, .control, .option])
    switch press.key {
    case .downArrow, .upArrow:
      store.select(.move(down: press.key == .downArrow, extend: press.modifiers.contains(.shift)))
      return .handled
    case .space:
      guard let cursor = store.selection.cursor else { return .ignored }
      store.select(.toggle(cursor))
      return .handled
    case .escape:
      // With something selected, Esc clears and stops there.
      if !store.selection.selected.isEmpty {
        store.select(.clear)
        return .handled
      }
      if store.openKey != nil {
        store.closeMessage()
        return .handled
      }
      return .ignored
    default:
      break
    }
    switch press.characters.lowercased() {
    case "a" where press.modifiers.contains(.command):
      store.select(.all)
      return .handled
    // E and M only act on what is marked: without a selection they do nothing,
    // so a delete is never confirmed for the wrong conversation by accident.
    case "e" where plain && !store.selection.selected.isEmpty:
      store.requestDeleteSelected(presenter: presenter)
      return .handled
    case "m" where plain && !store.selection.selected.isEmpty:
      store.requestMoveSelected(presenter: presenter)
      return .handled
    default:
      return .ignored
    }
  }
}

/// Where each selected row sits in the "maço" of the drag under way.
private struct DragStackLookup {
  let selected: Set<String>
  let positions: [String: Int]
  let dragged: Int?

  init(store: EmailStore, order: [String]) {
    guard let dragging = store.dragging else {
      selected = []
      positions = [:]
      dragged = nil
      return
    }
    selected = Set(store.selection.selected)
    var positions: [String: Int] = [:]
    for (index, id) in order.enumerated() where positions[id] == nil { positions[id] = index }
    self.positions = positions
    dragged = positions[dragging]
  }

  func placement(of id: String) -> EmailDragStack.Placement? {
    guard selected.contains(id), let index = positions[id] else { return nil }
    return EmailDragStack.placement(index: index, dragged: dragged)
  }
}

/// The header of a group, with its tri-state checkbox.
struct EmailGroupHeader: View {
  @Environment(\.theme) private var theme
  let store: EmailStore
  let group: EmailThreadGroup

  var body: some View {
    let ids = group.threads.map(\.id)
    let selected = Set(store.selection.selected)
    let all = ids.allSatisfy { selected.contains($0) }
    let some = ids.contains { selected.contains($0) }
    HStack(spacing: 10) {
      Button {
        store.select(.group(ids))
      } label: {
        Image(systemName: all ? "checkmark.square.fill" : (some ? "minus.square.fill" : "square"))
          .foregroundStyle(some ? theme.brand : theme.inkDim)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("selecionar todo o grupo \(group.label)")
      .accessibilityValue(all ? "marcado" : (some ? "parcial" : "desmarcado"))
      Text(group.label)
        .font(.daily(size: 12, weight: .semibold))
        .lineLimit(1)
        .accessibilityAddTraits(.isHeader)
      Text("\(group.threads.count)")
        .font(.daily(size: 12).monospacedDigit())
    }
    .foregroundStyle(theme.inkDim)
    .padding(.horizontal, 8)
    .padding(.top, 16)
    .padding(.bottom, 4)
  }
}

/// One conversation (`<li>` of the web list), and its messages or body when open.
struct EmailThreadRow: View {
  @Environment(\.theme) private var theme
  @Environment(\.emailPresenter) private var presenter
  let store: EmailStore
  let thread: EmailThread
  let group: EmailThreadGroup
  /// Position in the group, for the zebra of `ListRow`.
  let index: Int
  let isCursor: Bool
  /// Where the row goes in the "maço" while the selection is dragged; nil otherwise.
  var stack: EmailDragStack.Placement?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var title: String { thread.subject.isEmpty ? "(sem assunto)" : thread.subject }
  private var single: EmailEnvelope? { thread.messages.count == 1 ? thread.messages.first : nil }
  private var isSelected: Bool { store.selection.selected.contains(thread.id) }
  private var isOpen: Bool {
    if let single { return single.key == store.openKey }
    return store.expanded.contains(thread.id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      row
        .draggable(store.beginDrag(thread.id)) {
          EmailDragPreview(title: title, count: isSelected ? store.selection.selected.count : 1)
        }
        .contextMenu { EmailBatchContextMenu(store: store, thread: thread, group: group) }
      if let single, isOpen {
        EmailDetailView(store: store, message: single, tags: store.tags(of: thread))
      } else if isOpen {
        messages
      }
    }
    .background(isOpen ? theme.brandTint : .clear)
    // Who asked for less motion keeps the selection by colour and ring only
    // (`EmailPanel.tsx:1305-1309`).
    .scaleEffect(reduceMotion ? 1 : (stack?.scale ?? 1) as CGFloat)
    .offset(y: reduceMotion ? 0 : (stack?.offsetY ?? 0) as CGFloat)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: stack)
  }

  private var row: some View {
    let sent = thread.messages.count - thread.received.count
    let actionError = thread.messages.first { $0.actionError != nil }?.actionError
    return HStack(spacing: 12) {
      Circle()
        .fill(thread.unreadCount > 0 ? theme.brand : .clear)
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
      Toggle(
        "selecionar \(title)",
        isOn: Binding(
          get: { isSelected },
          set: { _ in
            // The checkbox always toggles; ⇧ on it still marks the range.
            if NSEvent.modifierFlags.contains(.shift) {
              store.select(.click(thread.id, shift: true))
            } else {
              store.select(.toggle(thread.id))
            }
          })
      )
      .toggleStyle(.checkbox)
      .labelsHidden()
      .accessibilityLabel("selecionar \(title)")
      Button {
        let flags = NSEvent.modifierFlags
        // With a modifier the click is selection; without, it opens.
        if flags.contains(.shift) || flags.contains(.command) || flags.contains(.control) {
          store.select(
            .click(thread.id, shift: flags.contains(.shift), meta: flags.contains(.command) || flags.contains(.control))
          )
        } else {
          store.activate(thread)
        }
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.daily(size: 14, weight: thread.unreadCount > 0 ? .medium : .regular))
            .foregroundStyle(thread.unreadCount > 0 ? theme.ink : theme.inkMid)
          Text(thread.participants.isEmpty ? "—" : thread.participants.joined(separator: ", "))
            .typeRole(.caption)
            .foregroundStyle(theme.inkDim)
          if let actionError {
            // The action that ran out of retries does not vanish quietly.
            Text(actionError)
              .typeRole(.caption)
              .foregroundStyle(theme.danger)
              .accessibilityAddTraits(.isStaticText)
          }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityValue(isOpen ? "aberta" : "fechada")
      if thread.messages.count > 1 {
        Text("\(thread.messages.count)")
          .typeRole(.caption)
          .monospacedDigit()
          .padding(.horizontal, 6)
          .foregroundStyle(thread.unreadCount > 0 ? theme.brand : theme.inkDim)
          .background(thread.unreadCount > 0 ? theme.brandTint : theme.neutralTint, in: .capsule)
          .overlay { Capsule().strokeBorder(thread.unreadCount > 0 ? theme.brandEdge : theme.lineStrong) }
          .accessibilityLabel(
            sent > 0
              ? "\(thread.messages.count) mensagens, \(sent) enviadas por você" : "\(thread.messages.count) mensagens")
      }
      Text(relative(thread.lastDate))
        .typeRole(.caption)
        .monospacedDigit()
        .foregroundStyle(theme.inkDim)
        .frame(minWidth: 36, alignment: .trailing)
      if store.mailboxes.count > 1, let label = thread.messages.first?.accountLabel {
        Badge(label, style: .secondary)
      }
      EmailTagButton(store: store, thread: thread, title: title)
      IconButton("excluir \(title)", systemImage: "trash", size: .small, variant: .destructive) {
        store.requestDelete(thread, presenter: presenter)
      }
      EmailCreateMenu(store: store, thread: thread, title: title)
    }
    .modifier(EmailRowShell(index: index, isOpen: isOpen, isSelected: isSelected, isCursor: isCursor))
    .opacity(store.dragging != nil && isSelected ? 0.7 : 1)
    // `shadow-e2` of a row in the "maço". Drawn on a clear shape behind the
    // row so the shadow never darkens the text, and always present so the
    // dragged row keeps its identity mid-drag.
    .background {
      Rectangle().fill(.clear)
        .elevation(.e2, in: Rectangle())
        .opacity(store.dragging != nil && isSelected ? 1 : 0)
        .allowsHitTesting(false)
    }
    .onHover { inside in
      // The tag menu and the move destinations need the account's folders.
      if inside, let account = thread.messages.first?.account {
        Task { await store.loadAccountFolders(account) }
      }
    }
  }

  private var messages: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(thread.messages, id: \.key) { message in
        let open = message.key == store.openKey
        Button {
          store.toggleOpen(message)
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(message.from.isEmpty ? "—" : message.from)
              .font(.daily(size: 14, weight: message.mailbox == .inbox && message.unread ? .medium : .regular))
              .foregroundStyle(
                message.mailbox == .sent ? theme.inkDim : (message.unread ? theme.ink : theme.inkMid)
              )
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
            if message.mailbox == .sent {
              Badge("enviada", style: .secondary)
            }
            Text(relative(message.date))
              .typeRole(.caption)
              .monospacedDigit()
              .foregroundStyle(theme.inkDim)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(open ? theme.brandTint : .clear)
        .accessibilityValue(open ? "aberta" : "fechada")
        if open {
          EmailDetailView(store: store, message: message, tags: store.tags(of: thread))
        }
      }
    }
    .padding(.leading, 36)
    .overlay(alignment: .leading) {
      Rectangle().fill(theme.lineSoft).frame(width: 1).padding(.leading, 36)
    }
  }

  private func relative(_ iso: String) -> String {
    let text = store.relativeTime(iso)
    return text.isEmpty ? "—" : text
  }
}

/// The right-click batch menu (`menuDoLote`). The clicked row joins the
/// selection first, so every item acts on what is marked.
struct EmailBatchContextMenu: View {
  @Environment(\.emailPresenter) private var presenter
  let store: EmailStore
  let thread: EmailThread
  let group: EmailThreadGroup

  var body: some View {
    let inSelection = store.selection.selected.contains(thread.id)
    let count = inSelection ? store.selection.selected.count : 1
    let folders =
      inSelection ? store.moveFolders : (thread.messages.first.flatMap { store.accountFolders[$0.account] } ?? [])
    let ids = group.threads.map(\.id)
    let wholeGroup = ids.allSatisfy { store.selection.selected.contains($0) }
    Text("\(count) \(count == 1 ? "conversa" : "conversas")")
      // The right click marks the row before the menu shows (`onContextMenu`
      // dispatching `context`, EM-16): the menu speaks of what is marked.
      .onAppear { store.select(.context(thread.id)) }
    Button("Marcar lido", systemImage: "envelope.open") { run(.read) }
    Button("Marcar não lido", systemImage: "envelope.badge") { run(.unread) }
    Menu("Mover para", systemImage: "folder") {
      ForEach(folders, id: \.self) { folder in
        Button(folder) { run(.move, folder: folder) }
      }
    }
    .disabled(folders.isEmpty)
    Divider()
    if store.filters.groupBy != .none && !wholeGroup {
      Button("Selecionar todo o grupo \(group.label)") { store.select(.group(ids)) }
    }
    Button("Limpar seleção") { store.select(.clear) }
    Divider()
    Button("Excluir", systemImage: "trash", role: .destructive) {
      store.select(.context(thread.id))
      store.requestDeleteSelected(presenter: presenter)
    }
  }

  private func run(_ action: EmailBatchAction, folder: String? = nil) {
    store.select(.context(thread.id))
    Task { await store.runBatch(action, folder: folder) }
  }
}

/// The tag picker of a conversation: the account's folders, loaded on first use.
struct EmailTagButton: View {
  @Environment(\.theme) private var theme
  let store: EmailStore
  let thread: EmailThread
  let title: String

  var body: some View {
    let account = thread.messages.first?.account ?? ""
    let tagged = !store.tags(of: thread).isEmpty
    let isOpen = store.tagMenuThread == thread.id
    Button {
      store.tagMenuThread = isOpen ? nil : thread.id
    } label: {
      // A tagged conversation keeps the brand glyph over the ghost style's ink.
      if tagged {
        Image(systemName: "tag.fill").foregroundStyle(theme.brand)
      } else {
        Image(systemName: "tag")
      }
    }
    .iconButtonStyle(size: .small, isActive: isOpen)
    .help("etiquetar \(title)")
    .accessibilityLabel("etiquetar \(title)")
    .popover(
      isPresented: Binding(
        get: { store.tagMenuThread == thread.id },
        set: { if !$0, store.tagMenuThread == thread.id { store.tagMenuThread = nil } })
    ) {
      tagList(account: account)
        .task { await store.loadAccountFolders(account) }
    }
  }

  @ViewBuilder
  private func tagList(account: String) -> some View {
    let folders = store.accountFolders[account] ?? []
    VStack(alignment: .leading, spacing: 2) {
      if let error = store.accountFoldersError[account], folders.isEmpty {
        Text(error)
          .font(.daily(size: 14))
          .foregroundStyle(theme.danger)
          .padding(8)
      } else if folders.isEmpty {
        Text("Carregando etiquetas…")
          .font(.daily(size: 14))
          .foregroundStyle(theme.inkDim)
          .padding(8)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(folders, id: \.self) { folder in
              Button {
                Task { await store.applyTag(folder, to: thread) }
              } label: {
                Text(folder)
                  .font(.daily(size: 14))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .contentShape(.rect)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(maxHeight: 320)
      }
    }
    .padding(6)
    .frame(minWidth: 180)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("etiquetas")
  }
}

/// "Criar a partir deste e-mail" (`components/email/CreateFromEmailMenu.tsx`).
/// A popover rather than a menu: the note folder is chosen inline before
/// creating, as the web's select inside the dropdown (EM-30), and the folders
/// load when it opens instead of once per row.
struct EmailCreateMenu: View {
  let store: EmailStore
  let thread: EmailThread
  let title: String
  @State private var isOpen = false

  var body: some View {
    Button {
      isOpen.toggle()
    } label: {
      Image(systemName: "ellipsis")
    }
    .iconButtonStyle(size: .small, isActive: isOpen)
    .help("Ações de \(title)")
    .accessibilityLabel("Ações de \(title)")
    .popover(isPresented: $isOpen, arrowEdge: .bottom) {
      EmailCreatePopover(store: store) { kind, folderId in
        isOpen = false
        Task { await store.create(kind, from: thread, noteFolderId: folderId) }
      }
      .task { await store.loadNoteFolders() }
    }
  }
}

/// The popover's content: the note folder, then the two creations.
struct EmailCreatePopover: View {
  @Environment(\.theme) private var theme
  let store: EmailStore
  let onCreate: (CreateKind, String?) -> Void
  /// nil is "Sem pasta".
  @State private var folderId: String?

  var body: some View {
    let busy = store.creating != nil
    VStack(alignment: .leading, spacing: 10) {
      Text("Criar a partir deste e-mail")
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .accessibilityAddTraits(.isHeader)
      Picker("Pasta da nota", selection: $folderId) {
        Text("Sem pasta").tag(String?.none)
        ForEach(store.noteFolders) { folder in
          Text(folder.name).tag(String?.some(folder.id))
        }
      }
      .pickerStyle(.menu)
      Divider()
      Button("Criar nota", systemImage: "note.text.badge.plus") { onCreate(.note, folderId) }
        .disabled(busy)
      Button("Criar tarefa", systemImage: "checklist") { onCreate(.task, nil) }
        .disabled(busy)
    }
    .buttonStyle(.borderless)
    .padding(12)
    .frame(width: 256, alignment: .leading)
  }
}

/// What follows the cursor: the "maço", the top subject on a card with the
/// sheets below it peeking out and how many go along (`mocoDeArraste`,
/// `EmailPanel.tsx:140-182`).
struct EmailDragPreview: View {
  @Environment(\.theme) private var theme
  let title: String
  let count: Int

  /// The offsets of the two sheets under the card, deepest first. Each is
  /// inset by a third of its offset (`6px 6px 0 -2px`, `12px 12px 0 -4px`).
  private static let sheetOffsets: [CGFloat] = [12, 6]

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 10)
    HStack(spacing: 8) {
      Text(title).lineLimit(1).truncationMode(.tail)
      if count > 1 {
        Text("\(count)")
          .font(.daily(size: 12).monospacedDigit())
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 1)
          .background(theme.brand, in: .capsule)
          .fixedSize()
      }
    }
    .font(.daily(size: 13, weight: .medium))
    .foregroundStyle(theme.ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    // `max-width: 20rem`.
    .frame(maxWidth: 320, alignment: .leading)
    .background(theme.surface2, in: shape)
    .overlay { shape.strokeBorder(theme.brandEdge) }
    .background {
      ZStack {
        ForEach(Self.sheetOffsets, id: \.self) { offset in
          shape
            .fill(theme.surface2)
            .overlay { shape.strokeBorder(theme.brandEdge) }
            .padding(offset / 3)
            .offset(x: offset, y: offset)
        }
      }
    }
    .shadow(color: .black.opacity(0.18), radius: 12, y: 10)
    // Room for the sheets and the shadow: the preview is a snapshot of these bounds.
    .padding(.trailing, 16)
    .padding(.bottom, 24)
    .padding([.top, .leading], 4)
    .accessibilityHidden(true)
  }
}

/// The conversation row on the shared `ListRow` (EM-7): zebra, brand tint on hover
/// and open, plus the two states only the e-mail list has, a marked row
/// (`bg-brand-tint/70`) and the keyboard cursor ring (`ring-1 ring-inset
/// ring-brand-edge`, `EmailPanel.tsx:1320-1326`).
private struct EmailRowShell: ViewModifier {
  @Environment(\.theme) private var theme
  let index: Int
  let isOpen: Bool
  let isSelected: Bool
  let isCursor: Bool

  func body(content: Content) -> some View {
    ListRow(index: index, isActive: isOpen) { content }
      // Behind the row's own fill, so hover still lights a marked row.
      .background(isSelected && !isOpen ? theme.brandTint.opacity(0.7) : .clear)
      .overlay {
        // Where the keyboard is, so the arrows do not walk blind.
        Rectangle().strokeBorder(theme.brandEdge).opacity(isCursor ? 1 : 0).allowsHitTesting(false)
      }
  }
}
