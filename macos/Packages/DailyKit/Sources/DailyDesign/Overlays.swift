import SwiftUI
import UniformTypeIdentifiers

// MARK: - Confirm dialog

/// One confirmation to ask (`ConfirmOptions` in `components/data/ConfirmDialog.tsx`).
/// Name the act in `confirmLabel` where you can instead of the plain default.
public struct ConfirmRequest: Identifiable {
  public let id = UUID()
  public var title: String
  public var message: String?
  public var confirmLabel: String
  public var cancelLabel: String
  /// Paints the confirm button as destructive. Deleting something is the case.
  public var destructive: Bool
  public var onConfirm: () -> Void
  public var onCancel: () -> Void

  public init(
    title: String,
    message: String? = nil,
    confirmLabel: String = "Confirmar",
    cancelLabel: String = "Cancelar",
    destructive: Bool = false,
    onConfirm: @escaping () -> Void,
    onCancel: @escaping () -> Void = {}
  ) {
    self.title = title
    self.message = message
    self.confirmLabel = confirmLabel
    self.cancelLabel = cancelLabel
    self.destructive = destructive
    self.onConfirm = onConfirm
    self.onCancel = onCancel
  }
}

extension View {
  /// Presents `request` as a sheet: Return confirms, Escape cancels, and any
  /// dismissal other than the confirm button counts as a "no", as on the web.
  public func confirmDialog(_ request: Binding<ConfirmRequest?>) -> some View {
    modifier(ConfirmDialogModifier(request: request))
  }
}

struct ConfirmDialogModifier: ViewModifier {
  @Binding var request: ConfirmRequest?
  @State private var confirmedID: UUID?

  func body(content: Content) -> some View {
    content.sheet(item: $request) { pending in
      ConfirmDialogView(
        request: pending,
        confirm: {
          confirmedID = pending.id
          request = nil
        },
        cancel: { request = nil }
      )
      // Settling on disappear covers every way the sheet can close (Escape, the
      // cancel button, the caller clearing the binding): only the confirm button
      // counts as a yes.
      .onDisappear {
        if confirmedID == pending.id {
          confirmedID = nil
          pending.onConfirm()
        } else {
          pending.onCancel()
        }
      }
    }
  }
}

/// The dialog body. Public so a preview or gallery can show it without a sheet.
public struct ConfirmDialogView: View {
  @Environment(\.theme) private var theme
  private let request: ConfirmRequest
  private let confirm: () -> Void
  private let cancel: () -> Void

  public init(request: ConfirmRequest, confirm: @escaping () -> Void, cancel: @escaping () -> Void) {
    self.request = request
    self.confirm = confirm
    self.cancel = cancel
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(request.title)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(theme.ink)
          .accessibilityAddTraits(.isHeader)
        if let message = request.message {
          Text(message)
            .font(.system(size: 14))
            .foregroundStyle(theme.inkMid)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        // Cancel first and quiet: the destructive act should never be where the
        // hand lands by habit. Each button prints the key it answers to.
        Button(action: cancel) {
          HStack(spacing: 6) {
            Text(request.cancelLabel)
            ShortcutKey("Esc")
          }
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.bordered)

        Button(role: request.destructive ? .destructive : nil, action: confirm) {
          HStack(spacing: 6) {
            Text(request.confirmLabel)
            ShortcutKey("Enter")
          }
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .tint(request.destructive ? theme.danger : theme.brand)
      }
    }
    .padding(24)
    .frame(width: 448)
    .background(theme.surface3)
  }
}

// MARK: - Toasts

/// One toast to show. Who keeps the list and when a toast expires is the caller's job.
public struct ToastMessage: Identifiable, Equatable {
  public enum Kind: String, Sendable, CaseIterable {
    case success, error, info
  }

  /// An optional action, such as "Desfazer".
  public struct Action {
    public var title: String
    public var perform: () -> Void

    public init(title: String, perform: @escaping () -> Void) {
      self.title = title
      self.perform = perform
    }
  }

  public let id: UUID
  public var kind: Kind
  public var text: String
  public var action: Action?

  public init(id: UUID = UUID(), kind: Kind, text: String, action: Action? = nil) {
    self.id = id
    self.kind = kind
    self.text = text
    self.action = action
  }

  /// Closures cannot be compared; two toasts are equal when they show the same thing.
  public static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
    lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.action?.title == rhs.action?.title
  }
}

/// One toast, styled like the web's sonner toaster (`components/ui/sonner.tsx`).
public struct ToastView: View {
  @Environment(\.theme) private var theme
  private let message: ToastMessage
  private let dismiss: () -> Void

  public init(_ message: ToastMessage, dismiss: @escaping () -> Void) {
    self.message = message
    self.dismiss = dismiss
  }

  public var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundStyle(tone)
        .accessibilityHidden(true)
      Text(message.text)
        .font(.system(size: 14))
        .foregroundStyle(theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let action = message.action {
        Button(action.title) {
          action.perform()
          dismiss()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      Button(action: dismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(theme.inkDim)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Fechar")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(width: 356)
    .background(theme.surface3, in: .rect(cornerRadius: theme.radius))
    .overlay { RoundedRectangle(cornerRadius: theme.radius).strokeBorder(theme.line) }
    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    .accessibilityElement(children: .contain)
    .onAppear { AccessibilityNotification.Announcement(message.text).post() }
  }

  /// The sonner icons of the web: CircleCheck, OctagonX, Info.
  private var icon: String {
    switch message.kind {
    case .success: "checkmark.circle"
    case .error: "xmark.octagon"
    case .info: "info.circle"
    }
  }

  private var tone: Color {
    switch message.kind {
    case .success: theme.success
    case .error: theme.danger
    case .info: theme.info
    }
  }
}

/// Renders the toasts it is given, newest at the bottom, in the window's
/// bottom-trailing corner. It holds no state of its own.
public struct ToastStack: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let messages: [ToastMessage]
  private let dismiss: (ToastMessage.ID) -> Void

  public init(_ messages: [ToastMessage], dismiss: @escaping (ToastMessage.ID) -> Void) {
    self.messages = messages
    self.dismiss = dismiss
  }

  public var body: some View {
    VStack(alignment: .trailing, spacing: 8) {
      ForEach(messages) { message in
        ToastView(message) { dismiss(message.id) }
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    .animation(Motion.ease(Motion.standard, reduceMotion: reduceMotion), value: messages)
  }
}

// MARK: - Drop target

/// A dashed drop zone (the focus-block target of `components/AgendaPanel.tsx`): it
/// lights up in the brand while something droppable hovers, and hands the dropped
/// payloads to the caller.
public struct FocusDropTarget<Payload: Transferable>: View {
  @Environment(\.theme) private var theme
  @State private var targeted = false
  private let label: String
  private let onDrop: ([Payload]) -> Void

  public init(_ label: String, for _: Payload.Type = Payload.self, onDrop: @escaping ([Payload]) -> Void) {
    self.label = label
    self.onDrop = onDrop
  }

  public var body: some View {
    Text(label)
      .font(.system(size: 14))
      .foregroundStyle(targeted ? theme.brand : theme.inkDim)
      .frame(maxWidth: .infinity)
      .padding(12)
      .background(targeted ? theme.brandTint : .clear, in: .rect(cornerRadius: Radius.large))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.large)
          .strokeBorder(targeted ? theme.brand : theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      }
      .dropDestination(for: Payload.self) { items, _ in
        guard !items.isEmpty else { return false }
        onDrop(items)
        return true
      } isTargeted: {
        targeted = $0
      }
  }
}

// MARK: - Backdrop

/// The window background: the radial mesh of `bg-mesh` (globals.css:908) or a flat
/// base, from `BackdropPalette`.
public struct BackdropView: View {
  @Environment(\.colorScheme) private var colorScheme
  private let backdrop: Backdrop

  public init(_ backdrop: Backdrop) {
    self.backdrop = backdrop
  }

  public var body: some View {
    let palette = BackdropPalette.resolve(scheme: colorScheme, backdrop: backdrop)
    ZStack {
      palette.base
      ForEach(Array(palette.blobs.enumerated()), id: \.offset) { _, blob in
        EllipticalGradient(
          colors: [blob.color, blob.color.opacity(0)],
          center: blob.center,
          startRadiusFraction: 0,
          // CSS sizes the ellipse to the farthest corner from the centre (√2 × the
          // farthest side on each axis); one fraction serves both axes here, so the
          // mean of the two is the closest single reach.
          endRadiusFraction: blob.stop * Self.farthestCornerReach(blob.center)
        )
      }
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }

  static func farthestCornerReach(_ center: UnitPoint) -> Double {
    let dx = max(center.x, 1 - center.x)
    let dy = max(center.y, 1 - center.y)
    return 2.0.squareRoot() * (dx + dy) / 2
  }
}
