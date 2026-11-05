import DailyDesign
import DailyModels
import SwiftUI

/// The folders of every account (`components/email/FolderTree.tsx`). A folder
/// accepts dragged conversations and offers to mark itself read.
struct EmailFolderTree: View {
  @Environment(\.theme) private var theme
  let store: EmailStore
  /// Collapsed accounts; open is the default.
  @State private var collapsed: Set<String> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(store.groups) { group in
        section(group)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Pastas")
  }

  private func section(_ group: MailboxGroup) -> some View {
    let open = !collapsed.contains(group.id)
    return VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Button {
          if open { collapsed.insert(group.id) } else { collapsed.remove(group.id) }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.right")
              .font(.system(size: 9, weight: .semibold))  // SF Symbol sizing
              .rotationEffect(.degrees(open ? 90 : 0))
            Text(group.account.label.uppercased())
              .font(.geist(11, weight: .medium))
              .tracking(0.5)
              .lineLimit(1)
          }
          .foregroundStyle(theme.inkDim)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.account.label)
        .accessibilityValue(open ? "expandida" : "recolhida")
        Spacer(minLength: 0)
        // The background read announces itself without taking anything away.
        if group.syncing {
          ProgressView()
            .controlSize(.mini)
            .accessibilityLabel("atualizando \(group.account.label)")
        }
      }
      .padding(.horizontal, 4)
      .padding(.bottom, 4)

      if let error = group.error {
        HStack(spacing: 8) {
          Text(error)
            .lineLimit(1)
            .foregroundStyle(theme.danger)
          Button("tentar de novo") { Task { await store.syncMailboxes(group.id) } }
            .buttonStyle(.link)
        }
        .typeRole(.caption)
        .padding(.horizontal, 8)
      }

      if open {
        if group.loading && group.mailboxes.isEmpty {
          caption("Carregando pastas…")
        } else if group.mailboxes.isEmpty && group.error == nil {
          caption("Nenhuma pasta.")
        } else {
          ForEach(group.mailboxes) { node in
            EmailFolderRow(store: store, account: group.account, node: node)
          }
        }
      }
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .typeRole(.caption)
      .foregroundStyle(theme.inkDim)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
  }
}

struct EmailFolderRow: View {
  @Environment(\.theme) private var theme
  let store: EmailStore
  let account: MailboxRef
  let node: MailboxNode
  @State private var targeted = false
  @State private var hovering = false
  @FocusState private var markReadFocused: Bool

  private var name: String { node.name.isEmpty ? node.path : node.name }
  private var selection: FolderSelection { FolderSelection(account: account.id, path: node.path) }

  var body: some View {
    let active = store.highlightedFolder == selection
    HStack(spacing: 4) {
      Button {
        Task { await store.openFolder(selection) }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: Self.symbol(for: node))
            .frame(width: 16)
            .foregroundStyle(theme.inkDim)
          Text(name)
            .lineLimit(1)
            .font(.geist(14, weight: active ? .medium : .regular))
          Spacer(minLength: 0)
        }
        .padding(.leading, 8 + CGFloat(Self.depth(of: node)) * 12)
        .padding(.vertical, 6)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      // The account tells same-named folders apart, and the count alone says nothing aloud.
      .accessibilityLabel(
        node.unread > 0 ? "\(name) em \(account.label), \(node.unread) não lidas" : "\(name) em \(account.label)"
      )
      .accessibilityAddTraits(active ? .isSelected : [])

      // Always laid out, a transparent "0" when empty, so names never shift (EM-24).
      CountSlot(node.unread)
      // The slot is kept even without the button, so the count does not dance.
      ZStack {
        if node.unread > 0 {
          Button {
            store.requestMarkFolderRead(account: account.id, node: node)
          } label: {
            Image(systemName: "envelope.open")
          }
          .iconButtonStyle(size: .extraSmall)
          .accessibilityLabel("Marcar a pasta \(name) de \(account.label) como lida")
          .focused($markReadFocused)
          // Shown when focused too, as the web's `focus-visible:opacity-100` (`FolderTree.tsx:248`).
          .opacity(hovering || markReadFocused ? 1 : 0)
          .help(
            "Marca como lidos os e-mails de \(name) em \(account.label), inclusive os que ainda não foram carregados aqui. Não é o mesmo que marcar os selecionados."
          )
        }
      }
      .frame(width: 28)
    }
    .font(.geist(14))
    .padding(.trailing, 2)
    // The web's active row, not a system selection (spec 013 FR-013-07).
    .activeRow(active)
    .background(targeted ? theme.brandTint : .clear, in: .rect(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6).strokeBorder(theme.brandEdge).opacity(targeted ? 1 : 0)
    }
    .onHover { hovering = $0 }
    .contextMenu {
      if node.unread > 0 {
        Button("Marcar a pasta como lida", systemImage: "envelope.open") {
          store.requestMarkFolderRead(account: account.id, node: node)
        }
      }
    }
    .dropDestination(for: EmailDragToken.self) { tokens, _ in
      guard !tokens.isEmpty else { return false }
      Task { await store.dropOnFolder(selection) }
      return true
    } isTargeted: {
      targeted = $0
    }
  }

  /// The icon comes from the special-use flag the server declares, not the
  /// name, which changes by provider and language.
  static func symbol(for node: MailboxNode) -> String {
    if node.path.uppercased() == "INBOX" { return "tray" }
    switch node.specialUse {
    case "\\Sent": return "paperplane"
    case "\\Trash": return "trash"
    case "\\Drafts": return "doc.text"
    case "\\Archive": return "archivebox"
    case "\\Junk": return "exclamationmark.octagon"
    default: return "folder"
    }
  }

  /// Depth comes from the path: the server separates levels with its delimiter.
  static func depth(of node: MailboxNode) -> Int {
    guard !node.delimiter.isEmpty else { return 0 }
    return node.path.components(separatedBy: node.delimiter).count - 1
  }
}

/// Where to drop what is being dragged (`components/email/ActionDropTargets.tsx`).
/// Each target is also a plain button, for the keyboard and for clicks.
struct EmailActionDropTargets: View {
  @Environment(\.theme) private var theme
  let store: EmailStore
  let count: Int

  private struct Target: Identifiable {
    var action: EmailBatchAction
    var label: String
    var text: String
    var hint: String
    var symbol: String
    var destructive = false
    var id: String { action.rawValue }
  }

  private let targets = [
    Target(
      action: .read, label: "Marcar como lido", text: "Lido", hint: "Solte para marcar como lido",
      symbol: "envelope.open"),
    Target(
      action: .unread, label: "Marcar como não lido", text: "Não lido", hint: "Solte para marcar como não lido",
      symbol: "envelope.badge"),
    Target(
      action: .delete, label: "Excluir as conversas arrastadas", text: "Excluir",
      hint: "Solte para mover para a lixeira", symbol: "trash", destructive: true),
  ]

  var body: some View {
    let noun = count == 1 ? "conversa" : "conversas"
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        Text("\(count)")
          .padding(.horizontal, 6)
          .background(theme.brandTint, in: .capsule)
          .overlay { Capsule().strokeBorder(theme.brandEdge) }
        Text(noun)
      }
      .typeRole(.caption)
      .monospacedDigit()
      .foregroundStyle(theme.brand)
      ForEach(targets) { target in
        EmailDropTargetButton(
          label: target.label, text: target.text, hint: target.hint, symbol: target.symbol,
          destructive: target.destructive
        ) {
          Task { await store.dropOnAction(target.action) }
        }
      }
    }
    .padding(8)
    .background(theme.brandTint.opacity(0.4), in: .rect(cornerRadius: Radius.small))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.small)
        .strokeBorder(theme.brandEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Soltar \(count) \(noun) em uma ação")
  }
}

private struct EmailDropTargetButton: View {
  @Environment(\.theme) private var theme
  let label: String
  let text: String
  let hint: String
  let symbol: String
  let destructive: Bool
  let action: () -> Void
  @State private var targeted = false

  var body: some View {
    let tint = destructive ? theme.danger : theme.brand
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
        Text(targeted ? hint : text).lineLimit(1)
      }
      .frame(maxWidth: .infinity, minHeight: 28)
      .foregroundStyle(targeted ? tint : theme.inkMid)
      .background(targeted ? tint.opacity(0.1) : .clear, in: .rect(cornerRadius: 6))
      .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(targeted ? tint : theme.lineStrong) }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .dropDestination(for: EmailDragToken.self) { tokens, _ in
      guard !tokens.isEmpty else { return false }
      action()
      return true
    } isTargeted: {
      targeted = $0
    }
  }
}
