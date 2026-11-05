import DailyCore
import DailyDesign
import SwiftUI

/// The notes module on its own (sidebar or window): the Início panel with the
/// screen's padding, on the same store. The window is already the large view,
/// so "Maximizar" stays in the panel.
public struct NotesScreen: View {
  private let store: NotesStore
  private let navigator: AppNavigator

  public init(environment: AppEnvironment) {
    self.init(store: NotesStore.shared(in: environment), navigator: environment.navigator)
  }

  init(store: NotesStore, navigator: AppNavigator) {
    self.store = store
    self.navigator = navigator
  }

  public var body: some View {
    NotesPanel(store: store, navigator: navigator, onOpenWindow: nil, canMaximize: false)
      .padding(20)
  }
}

#Preview("Notas") {
  NotesScreen(store: NotesPreview.store(), navigator: AppNavigator())
    .frame(width: 900, height: 600)
}
