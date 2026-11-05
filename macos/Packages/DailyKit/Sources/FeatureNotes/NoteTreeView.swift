import DailyDesign
import DailyModels
import SwiftUI

/// The folders and notes (`components/notes/NoteTree.tsx`). Selecting a note opens
/// it; selecting a folder or a view makes it the scope. Double click or Return
/// renames; the "…" button, the context menu and the keys of `NoteTreeShortcut`
/// hold the rest; rows drag onto folders.
///
/// The rows draw the web's active row rather than a `List` selection (NT-8), so the
/// tree walks its own arrows: ↑/↓ move the cursor, which selects as a list would.
struct NoteTreeView: View {
  @Bindable var store: NotesStore
  let onDeleteNote: (Note) -> Void
  let onDeleteFolder: (String) -> Void

  @State private var selection: String?
  @State private var dropTarget: String?
  @State private var hovered: String?
  /// The row whose action list the keyboard opened (⌃Return).
  @State private var actionListKey: String?
  @FocusState private var focused: Bool
  @Environment(\.theme) private var theme

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(store.rows) { row in
            rowView(row)
              .modifier(chrome(for: row))
              .id(row.id)
              // The rename field keeps its own clicks: selecting would take its focus.
              .modifier(
                RowSelection(
                  isSelectable: !isEmptyRow(row) && !isRenaming(row),
                  onClick: {
                    selection = row.id
                    focused = true
                  },
                  onDoubleClick: { startRenaming(row.id) })
              )
              .contextMenu {
                if !items(for: row.id).isEmpty { contextMenu(for: row.id) }
              }
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
      }
      .focusable()
      .focused($focused)
      .focusEffectDisabled()
      .accessibilityElement(children: .contain)
      .accessibilityLabel("pastas e notas")
      .onChange(of: selection) { _, key in
        guard let key else { return }
        proxy.scrollTo(key)
        select(key)
      }
      .onChange(of: store.activeID, initial: true) { _, id in
        // A note opened elsewhere (created, or the first after a delete) becomes the selection.
        guard let id, selection != NoteTreeRow.noteKey(id) else { return }
        selection = NoteTreeRow.noteKey(id)
      }
      .onKeyPress(.leftArrow) { setExpanded(false) }
      .onKeyPress(.rightArrow) { setExpanded(true) }
      .onKeyPress(keys: [.return, .delete, .deleteForward, .upArrow, .downArrow, "n", "N"]) { press in
        if let shortcut = NoteTreeShortcut.command(character: press.key.character, modifiers: press.modifiers) {
          return handle(shortcut)
        }
        return moveCursor(press)
      }
    }
  }

  /// Plain ↑/↓ walk the rows that can be chosen, skipping "pasta vazia".
  private func moveCursor(_ press: KeyPress) -> KeyPress.Result {
    guard store.renaming == nil, press.key == .upArrow || press.key == .downArrow,
      press.modifiers.isDisjoint(with: [.command, .option, .control, .shift])
    else { return .ignored }
    let ids = store.rows.filter { !isEmptyRow($0) }.map(\.id)
    guard let next = ListCursor.step(from: selection, in: ids, by: press.key == .downArrow ? 1 : -1) else {
      return .ignored
    }
    selection = next
    return .handled
  }

  /// What the row looks like: the open note is the active row (`NoteTree.tsx:143-149`),
  /// the current folder or view is `bg-brand-tint text-brand` (:210), and the
  /// keyboard cursor keeps a ring while the tree has focus.
  private func chrome(for row: NoteTreeRow) -> NoteTreeRowChrome {
    let look: NoteTreeRowChrome.Look
    switch row {
    case .all: look = .scope(current: store.scope == .all)
    case .none: look = .scope(current: store.scope == .none)
    case .folder(let folder, _, _, _):
      look = store.renaming == folder.id ? .plain : .scope(current: store.scope == .folder(folder.id))
    case .note(let note, _):
      look = store.renaming == note.id ? .plain : .note(active: note.id == store.activeID)
    case .empty: look = .plain
    }
    return NoteTreeRowChrome(look: look, isCursor: focused && selection == row.id)
  }

  // MARK: - Rows

  @ViewBuilder private func rowView(_ row: NoteTreeRow) -> some View {
    switch row {
    case .all(let count):
      line(depth: 0, chevron: nil) {
        icon("square.stack.3d.up")
        title("Todas as notas", current: store.scope == .all)
        Spacer(minLength: 4)
        countLabel(count)
      }
    case .none(let count, let expanded):
      line(depth: 0, chevron: chevron(NoteTreeRow.noneKey, expanded: expanded, name: "sem pasta")) {
        icon("tray")
        title("Sem pasta", current: store.scope == .none)
        Spacer(minLength: 4)
        countLabel(count)
      }
      .modifier(DropModifier(key: row.id, target: $dropTarget) { item in drop(item, intoFolder: nil) })
    case .folder(let folder, let depth, let noteCount, let expanded):
      if store.renaming == folder.id {
        RenameField(initial: folder.name, label: "renomear pasta \(folder.name)") { name in
          store.renaming = nil
          if let name { Task { await store.renameFolder(folder.id, to: name) } }
        }
        .padding(.leading, indent(depth))
      } else {
        line(depth: depth, chevron: chevron(folder.id, expanded: expanded, name: folder.name)) {
          icon(expanded ? "folder.fill" : "folder")
          title(folder.name, current: store.scope == .folder(folder.id))
          Spacer(minLength: 4)
          if noteCount > 0 { countLabel(noteCount) }
          actionsButton(key: row.id, label: NoteTreeActions.label(for: folder))
        }
        .modifier(RowActions(items: items(for: row.id)) { perform($0, on: row.id) })
        .draggable(NoteTreeItem.folder(folder.id)) { dragPreview(folder.name, systemImage: "folder") }
        .modifier(DropModifier(key: row.id, target: $dropTarget) { item in drop(item, intoFolder: folder.id) })
      }
    case .note(let note, let depth):
      if store.renaming == note.id {
        RenameField(initial: note.title, label: "renomear \(displayTitle(note))") { title in
          store.renaming = nil
          if let title { Task { await store.renameNote(note.id, to: title) } }
        }
        .padding(.leading, indent(depth))
      } else {
        line(depth: depth, chevron: nil) {
          icon("doc.text")
          Text(displayTitle(note))
            .lineLimit(1)
          Spacer(minLength: 0)
          actionsButton(key: row.id, label: NoteTreeActions.label(for: note))
        }
        .help("Clique duplo para renomear")
        .modifier(RowActions(items: items(for: row.id)) { perform($0, on: row.id) })
        .accessibilityAddTraits(note.id == store.activeID ? .isSelected : [])
        .draggable(NoteTreeItem.note(note.id)) { dragPreview(displayTitle(note), systemImage: "doc.text") }
        .modifier(
          DropModifier(key: row.id, target: $dropTarget, acceptsFolders: false) { item in
            guard case .note(let id) = item else { return false }
            Task { await store.dropNote(id, before: note.id) }
            return true
          })
      }
    case .empty(_, let depth):
      Text("pasta vazia")
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
        .padding(.leading, indent(depth) + 40)
    }
  }

  private func line<Content: View>(
    depth: Int, chevron: AnyView?, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 6) {
      if let chevron { chevron } else { Color.clear.frame(width: 16, height: 1) }
      content()
    }
    .padding(.leading, indent(depth))
    .contentShape(.rect)
  }

  /// The web's "…" (`NoteMenu`/`FolderMenu`): shown on hover and on the selected
  /// row, the keyboard's equivalent of the web's `focus-visible`.
  private func actionsButton(key: String, label: String) -> some View {
    Menu {
      ForEach(items(for: key)) { item in menuButton(item, label: item.label, key: key) }
    } label: {
      Image(systemName: "ellipsis")
    }
    .menuStyle(.button)
    .menuIndicator(.hidden)
    .iconButtonStyle(size: .extraSmall, isActive: actionListKey == key)
    .fixedSize()
    .opacity(hovered == key || selection == key || actionListKey == key ? 1 : 0)
    .help(label)
    .accessibilityLabel(label)
    .onHover { inside in
      if inside {
        hovered = key
      } else if hovered == key {
        hovered = nil
      }
    }
    .popover(
      isPresented: Binding(
        get: { actionListKey == key },
        set: { if !$0, actionListKey == key { actionListKey = nil } }),
      arrowEdge: .trailing
    ) {
      NoteTreeActionList(label: label, items: items(for: key)) { action in
        actionListKey = nil
        perform(action, on: key)
      }
    }
  }

  private func chevron(_ key: String, expanded: Bool, name: String) -> AnyView {
    AnyView(
      Button {
        store.toggle(key)
      } label: {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
          .font(.system(size: 10, weight: .semibold))  // SF Symbol sizing
          .foregroundStyle(theme.inkDim)
          .frame(width: 16, height: 16)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(expanded ? "Recolher" : "Expandir") \(name)")
      .accessibilityValue(expanded ? "aberta" : "fechada"))
  }

  private func icon(_ systemImage: String) -> some View {
    Image(systemName: systemImage)
      .foregroundStyle(theme.inkDim)
      .frame(width: 16)
      .accessibilityHidden(true)
  }

  private func title(_ text: String, current: Bool) -> some View {
    Text(text)
      .lineLimit(1)
      .font(.daily(size: 14, weight: current ? .medium : .regular))
      .foregroundStyle(current ? theme.brand : theme.inkMid)
      .accessibilityAddTraits(current ? .isSelected : [])
  }

  private func countLabel(_ count: Int) -> some View {
    Text("\(count)")
      .typeRole(.caption)
      .monospacedDigit()
      .foregroundStyle(theme.inkDim)
  }

  private func dragPreview(_ text: String, systemImage: String) -> some View {
    Label(text, systemImage: systemImage)
      .padding(6)
      .background(theme.surface2, in: .rect(cornerRadius: Radius.small))
  }

  private func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 12 }

  private func displayTitle(_ note: Note) -> String { note.title.isEmpty ? "sem título" : note.title }

  private func isRenaming(_ row: NoteTreeRow) -> Bool {
    switch row {
    case .folder(let folder, _, _, _): store.renaming == folder.id
    case .note(let note, _): store.renaming == note.id
    case .all, .none, .empty: false
    }
  }

  private func isEmptyRow(_ row: NoteTreeRow) -> Bool {
    if case .empty = row { true } else { false }
  }

  // MARK: - Menus

  private func items(for key: String) -> [NoteTreeMenuItem] {
    if let note = note(for: key) {
      return NoteTreeActions.items(
        for: note, folders: store.folders,
        canShiftUp: store.canShiftNote(note.id, by: -1), canShiftDown: store.canShiftNote(note.id, by: 1))
    }
    if let folder = folder(for: key) { return NoteTreeActions.items(for: folder, folders: store.folders) }
    return []
  }

  /// The native menu groups the destinations under "Mover para".
  @ViewBuilder private func contextMenu(for key: String) -> some View {
    let items = items(for: key)
    let moves = items.filter(\.action.isMove)
    ForEach(items.filter { !$0.action.isMove && !$0.isDestructive }) { item in
      menuButton(item, label: item.label, key: key)
    }
    if !moves.isEmpty {
      Divider()
      Menu("Mover para") {
        ForEach(moves) { item in menuButton(item, label: item.shortLabel, key: key) }
      }
    }
    Divider()
    ForEach(items.filter(\.isDestructive)) { item in menuButton(item, label: item.label, key: key) }
  }

  private func menuButton(_ item: NoteTreeMenuItem, label: String, key: String) -> some View {
    Button(label, role: item.isDestructive ? .destructive : nil) { perform(item.action, on: key) }
      .disabled(!item.isEnabled)
  }

  // MARK: - Actions

  private func perform(_ action: NoteTreeAction, on key: String) {
    if let note = note(for: key) {
      switch action {
      case .rename: store.renaming = note.id
      case .moveNote(let folderID): Task { await store.moveNote(note.id, to: folderID) }
      case .shiftNote(let offset): Task { await store.shiftNote(note.id, by: offset) }
      case .deleteNote: onDeleteNote(note)
      case .newSubfolder, .moveFolder, .deleteFolder: break
      }
    } else if let folder = folder(for: key) {
      switch action {
      case .rename: store.renaming = folder.id
      case .newSubfolder:
        store.expanded.insert(folder.id)
        Task { await store.createFolder(in: folder.id) }
      case .moveFolder(let parentID): Task { await store.moveFolder(folder.id, to: parentID) }
      case .deleteFolder: onDeleteFolder(folder.id)
      case .moveNote, .shiftNote, .deleteNote: break
      }
    }
  }

  /// Runs a key on the selected row, only when that row offers the action.
  private func handle(_ shortcut: NoteTreeShortcut?) -> KeyPress.Result {
    // The rename field lives inside the list: its keys are its own.
    guard let shortcut, let key = selection, store.renaming == nil else { return .ignored }
    let available = items(for: key).filter(\.isEnabled).map(\.action)
    let action: NoteTreeAction
    switch shortcut {
    case .showActions:
      guard !available.isEmpty else { return .ignored }
      actionListKey = key
      return .handled
    case .rename: action = .rename
    case .delete: action = note(for: key) != nil ? .deleteNote : .deleteFolder
    case .shift(let offset): action = .shiftNote(by: offset)
    case .newSubfolder: action = .newSubfolder
    }
    guard available.contains(action) else { return .ignored }
    perform(action, on: key)
    return .handled
  }

  private func select(_ key: String) {
    switch key {
    case NoteTreeRow.allKey: store.scope = .all
    case NoteTreeRow.noneKey: store.scope = .none
    default:
      if let note = note(for: key) {
        Task { await store.open(note.id) }
      } else if let folder = folder(for: key) {
        store.scope = .folder(folder.id)
      }
    }
  }

  private func startRenaming(_ key: String) {
    if let note = note(for: key) {
      store.renaming = note.id
    } else if let folder = folder(for: key) {
      store.renaming = folder.id
    }
  }

  private func setExpanded(_ open: Bool) -> KeyPress.Result {
    guard let selection else { return .ignored }
    let key: String
    if selection == NoteTreeRow.noneKey {
      key = NoteTreeRow.noneKey
    } else if let folder = folder(for: selection) {
      key = folder.id
    } else {
      return .ignored
    }
    guard store.expanded.contains(key) != open else { return .ignored }
    store.toggle(key)
    return .handled
  }

  private func drop(_ item: NoteTreeItem, intoFolder folderID: String?) -> Bool {
    switch item {
    case .note(let id):
      Task { await store.moveNote(id, to: folderID) }
      return true
    case .folder(let id):
      guard id != folderID else { return false }
      Task { await store.moveFolder(id, to: folderID) }
      return true
    }
  }

  private func note(for key: String) -> Note? {
    store.notes.first { NoteTreeRow.noteKey($0.id) == key }
  }

  private func folder(for key: String) -> NoteFolder? {
    store.folders.first { NoteTreeRow.folderKey($0.id) == key }
  }
}

/// Accepts tree items and highlights the row while one hovers it.
private struct DropModifier: ViewModifier {
  let key: String
  @Binding var target: String?
  var acceptsFolders = true
  let perform: (NoteTreeItem) -> Bool
  @Environment(\.theme) private var theme

  func body(content: Content) -> some View {
    content
      .padding(.vertical, 1)
      .background {
        if target == key {
          RoundedRectangle(cornerRadius: 6)
            .fill(theme.brandTint)
            .strokeBorder(theme.brand.opacity(0.6))
        }
      }
      .dropDestination(for: NoteTreeItem.self) { items, _ in
        guard let item = items.first else { return false }
        if case .folder = item, !acceptsFolders { return false }
        return perform(item)
      } isTargeted: { hovering in
        if hovering {
          target = key
        } else if target == key {
          target = nil
        }
      }
  }
}

/// The inline name editor. Return or leaving the field commits, Escape cancels
/// (`NoteTree.tsx:118-131`). nil means cancelled.
struct RenameField: View {
  let initial: String
  let label: String
  let onFinish: (String?) -> Void

  @State private var text: String
  @State private var finished = false
  @FocusState private var focused: Bool

  init(initial: String, label: String, onFinish: @escaping (String?) -> Void) {
    self.initial = initial
    self.label = label
    self.onFinish = onFinish
    _text = State(initialValue: initial)
  }

  var body: some View {
    TextField(label, text: $text)
      .textFieldStyle(.roundedBorder)
      .labelsHidden()
      .accessibilityLabel(label)
      .focused($focused)
      .onAppear { focused = true }
      .onSubmit { finish(text) }
      .onExitCommand { finish(nil) }
      .onChange(of: focused) { _, isFocused in
        if !isFocused { finish(text) }
      }
  }

  private func finish(_ value: String?) {
    guard !finished else { return }
    finished = true
    onFinish(value)
  }
}

/// The row's actions as VoiceOver actions, so the rotor lists them on the row itself.
private struct RowActions: ViewModifier {
  let items: [NoteTreeMenuItem]
  let perform: (NoteTreeAction) -> Void

  func body(content: Content) -> some View {
    content.accessibilityActions {
      ForEach(items.filter(\.isEnabled)) { item in
        Button(item.label) { perform(item.action) }
      }
    }
  }
}

/// The row's actions opened from the keyboard (⌃Return): arrows choose, Return
/// runs, Escape closes. A list, because a SwiftUI `Menu` cannot be opened by a key.
struct NoteTreeActionList: View {
  let label: String
  let items: [NoteTreeMenuItem]
  let perform: (NoteTreeAction) -> Void

  @State private var selection: NoteTreeAction?
  @FocusState private var focused: Bool
  @Environment(\.theme) private var theme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(items) { item in
          Text(item.label)
            .font(.daily(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .activeRow(selection == item.action)
            // After `activeRow`, so a destructive or disabled item keeps its colour.
            .foregroundStyle(item.isEnabled ? (item.isDestructive ? theme.danger : theme.ink) : theme.inkDim)
            .contentShape(.rect)
            .onTapGesture {
              guard item.isEnabled else { return }
              perform(item.action)
            }
            .accessibilityAddTraits(.isButton)
        }
      }
      .padding(6)
    }
    .focusable()
    .focused($focused)
    .focusEffectDisabled()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
    .frame(width: 280, height: min(CGFloat(items.count) * 26 + 12, 360))
    .onAppear {
      selection = items.first(where: \.isEnabled)?.action
      focused = true
    }
    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
      let enabled = items.filter(\.isEnabled).map(\.action)
      selection = ListCursor.step(from: selection, in: enabled, by: press.key == .downArrow ? 1 : -1)
      return .handled
    }
    .onKeyPress(.return) {
      guard let selection else { return .ignored }
      perform(selection)
      return .handled
    }
  }
}

/// The look of a tree row; see `NoteTreeView.chrome(for:)`.
private struct NoteTreeRowChrome: ViewModifier {
  enum Look {
    case plain
    case note(active: Bool)
    case scope(current: Bool)
  }

  let look: Look
  let isCursor: Bool
  @Environment(\.theme) private var theme
  @State private var hovering = false

  func body(content: Content) -> some View {
    styled(
      content
        .font(.daily(size: 14))
        // `ROW` (`NoteTree.tsx:66-67`): `py-1.5 pr-1`, the indent starting at 0.5rem.
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    )
    .clipShape(.rect(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(theme.brandEdge)
        .opacity(isCursor ? 1 : 0)
        .allowsHitTesting(false)
    }
  }

  @ViewBuilder private func styled(_ row: some View) -> some View {
    switch look {
    case .plain:
      row
    case .note(let active):
      row.activeRow(active)
    case .scope(let current):
      // `hover:bg-glass-line` when not current; `--glass-line` stands in as line-soft.
      row
        .background(current ? theme.brandTint : (hovering ? ActiveRowStyle.hoverFill(theme: theme) : .clear))
        .onHover { hovering = $0 }
    }
  }
}

/// Click selects, double click renames, as the `List` primary action did. The double
/// click runs beside the single one so the first click selects without a delay.
private struct RowSelection: ViewModifier {
  let isSelectable: Bool
  let onClick: () -> Void
  let onDoubleClick: () -> Void

  func body(content: Content) -> some View {
    if isSelectable {
      content
        .contentShape(.rect)
        .onTapGesture(perform: onClick)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onDoubleClick))
        .accessibilityAction(.default, onClick)
    } else {
      content
    }
  }
}
