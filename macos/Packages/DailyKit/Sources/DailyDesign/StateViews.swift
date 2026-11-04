import SwiftUI

/// The zero state of a list (`components/data/EmptyState.tsx`): a dashed, translucent
/// well that points at the primary action, not a shrug.
public struct EmptyState<Action: View>: View {
  @Environment(\.theme) private var theme
  private let title: String
  private let description: String?
  private let systemImage: String?
  private let action: Action

  public init(
    _ title: String,
    description: String? = nil,
    systemImage: String? = nil,
    @ViewBuilder action: () -> Action
  ) {
    self.title = title
    self.description = description
    self.systemImage = systemImage
    self.action = action()
  }

  public var body: some View {
    VStack(spacing: 16) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(.system(size: 32))
          .foregroundStyle(theme.inkDim)
          .accessibilityHidden(true)
      }
      VStack(spacing: 6) {
        Text(title)
          .typeRole(.subhead)
          .foregroundStyle(theme.ink)
          .accessibilityAddTraits(.isHeader)
        if let description {
          Text(description)
            .font(.system(size: 14))
            .foregroundStyle(theme.inkMid)
            .frame(maxWidth: 384)
        }
      }
      .multilineTextAlignment(.center)
      action
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 64)
    .padding(.horizontal, 16)
    // The web well is `bg-muted/35`; `--muted` is not a Theme token, and line-soft is
    // the same primitive in Catppuccin and Dracula and within a few L points elsewhere.
    .background(theme.lineSoft.opacity(0.35), in: .rect(cornerRadius: Radius.extraLarge))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.extraLarge)
        .strokeBorder(theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
    .accessibilityElement(children: .contain)
  }
}

extension EmptyState where Action == EmptyView {
  public init(_ title: String, description: String? = nil, systemImage: String? = nil) {
    self.init(title, description: description, systemImage: systemImage) { EmptyView() }
  }
}

/// A failed fetch, shown inside the page chrome (`components/data/ErrorState.tsx`).
/// Retry is a quiet bordered button: retrying is not the dangerous act.
public struct ErrorState: View {
  @Environment(\.theme) private var theme
  private let title: String
  private let description: String?
  private let retry: (() -> Void)?

  public init(_ title: String, description: String? = nil, retry: (() -> Void)? = nil) {
    self.title = title
    self.description = description
    self.retry = retry
  }

  public var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 32))
        .foregroundStyle(theme.danger)
        .accessibilityHidden(true)
      VStack(spacing: 4) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(theme.ink)
          .accessibilityAddTraits(.isHeader)
        if let description {
          Text(description)
            .font(.system(size: 14))
            .foregroundStyle(theme.inkMid)
            .frame(maxWidth: 384)
        }
      }
      .multilineTextAlignment(.center)
      if let retry {
        Button("Tentar de novo", action: retry)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 64)
    .padding(.horizontal, 16)
    .background(theme.danger.opacity(0.05), in: .rect(cornerRadius: Radius.large))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.large).strokeBorder(theme.danger.opacity(0.4))
    }
    .accessibilityElement(children: .contain)
    // The web marks this `role="alert"`; VoiceOver hears it when it appears.
    .onAppear { AccessibilityNotification.Announcement(title).post() }
  }
}

/// A partial failure inside a panel that still shows data (`components/data/PanelError.tsx`).
/// Warning, not danger: a degraded fetch is not a destroyed record.
public struct PanelError: View {
  @Environment(\.theme) private var theme
  private let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var body: some View {
    Text(message)
      .font(.system(size: 14))
      .lineSpacing(14 * (1.625 - 1.2))
      .foregroundStyle(theme.inkMid)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(theme.warningTint)
      .overlay(alignment: .leading) {
        Rectangle().fill(theme.warning).frame(width: 2)
      }
      .clipShape(.rect(cornerRadius: Radius.small))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.small).strokeBorder(theme.warning.opacity(0.4))
      }
      .onAppear { AccessibilityNotification.Announcement(message).post() }
  }
}

/// A fetch in flight. The web shows skeletons or "Carregando…" inline; the native
/// app uses the system spinner with the same word.
public struct LoadingState: View {
  @Environment(\.theme) private var theme
  private let label: String

  public init(_ label: String = "Carregando…") {
    self.label = label
  }

  public var body: some View {
    HStack(spacing: 8) {
      ProgressView().controlSize(.small)
      Text(label)
        .typeRole(.caption)
        .foregroundStyle(theme.inkDim)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
    .accessibilityElement(children: .combine)
  }
}
