import AppKit
import DailyDesign
import DailyModels
import SwiftUI

/// The home "Abas" mode (`components/dashboard/WorkspaceHome.tsx`, Trellis'
/// `Workspace`): the panels as tabs in groups, inside splits whose dividers
/// resize them. A tab is selected by clicking it, cycled with ⌃Tab / ⌃⇧Tab in
/// the focused group, and dragged onto another group's strip (move), the middle
/// of a group (join it) or a group's edge (split it); Esc, or the window no
/// longer being active, cancels the drag (Trellis: Escape and `blur`). Inside
/// its own strip the tab is reordered in place, its siblings sliding aside.
/// Tabs do not close and each module appears once (`singleton`, `closable={false}`).
///
/// The drag is an in-app gesture read in the canvas' coordinate space, not
/// system drag and drop: a tab never leaves the window, and a custom content
/// type would need an Info.plist declaration. `layout` changes only through
/// `WorkspaceLayout`'s operations; persisting it is the host's job.
///
/// The host gives it a bounded height (the web uses `100dvh - 14rem`, at least
/// 480px): it fills what it is offered and never scrolls itself.
struct WorkspaceTabsView: View {
  /// Distance before a press on a tab becomes a drag, so a click still selects.
  private static let dragThreshold: CGFloat = 4
  /// Arrow keys or VoiceOver move a divider by this share of its split.
  private static let keyboardStep = 0.02

  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.appearsActive) private var appearsActive
  @Binding private var layout: WorkspaceLayout
  private let modules: [ModuleID]
  private let title: (ModuleID) -> String
  private let panel: (ModuleID) -> AnyView

  @State private var tabFrames: [ModuleID: CGRect] = [:]
  @State private var drag: TabDrag?
  /// Set by a cancel until the pointer is released, so the rest of that gesture is ignored.
  @State private var dragCancelled = false
  /// True while a tab's drag gesture is alive. Its start clears a stale
  /// `dragCancelled`: a gesture cut short when the window lost key status may
  /// never deliver the `onEnded` that would.
  @GestureState private var tabGestureLive = false
  @State private var resize: DividerResize?
  @FocusState private var focusedDivider: String?
  /// The divider whose focus came from the keyboard, the only focus it shows:
  /// a divider also takes focus when clicked or dragged.
  @State private var keyboardDivider: String?
  /// The group ⌃Tab acts on and whose selected tab carries the accent.
  @State private var focusedGroupID: String?

  init(
    modules: [ModuleID],
    title: @escaping (ModuleID) -> String,
    panel: @escaping (ModuleID) -> AnyView,
    layout: Binding<WorkspaceLayout>
  ) {
    self.modules = modules
    self.title = title
    self.panel = panel
    _layout = layout
  }

  var body: some View {
    GeometryReader { proxy in
      canvas(WorkspaceGeometry(root: layout.root, size: proxy.size), size: proxy.size)
    }
    .coordinateSpace(.named(WorkspaceChrome.coordinateSpace))
    .pointerStyle(drag == nil ? nil : PointerStyle.grabActive)
    .background { shortcuts }
    .onChange(of: modules, initial: true) { reconcile() }
    .onChange(of: appearsActive) { _, active in
      if !active && drag != nil { cancelDrag() }
    }
    .onChange(of: tabGestureLive) { _, live in
      if live { dragCancelled = false }
    }
    .onChange(of: focusedDivider) { _, focused in
      // Tab focus arrives on a key event; a click or drag does not.
      keyboardDivider = NSApp.currentEvent?.type == .keyDown ? focused : nil
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Painéis do Início")
  }

  // MARK: - Canvas

  /// Back to front: the groups' glass and tab strips, the panels, the dividers,
  /// then the drop indicator and the dragged tab.
  private func canvas(_ geometry: WorkspaceGeometry, size: CGSize) -> some View {
    let resolver = TabDropResolver(geometry: geometry, layout: layout, tabFrames: tabFrames)
    return WorkspaceCanvas(size: size) {
      ForEach(geometry.groups) { placed in
        if let group = layout.group(id: placed.id) {
          groupChrome(group, height: placed.strip.height, resolver: resolver)
            .workspaceCanvasFrame(placed.frame)
        }
      }
      // Keyed by module, not by group: a tab moved to another group keeps its
      // panel, and the hidden tabs stay mounted as they do in Trellis.
      ForEach(panelSlots(geometry)) { slot in
        panelView(slot)
          .workspaceCanvasFrame(slot.content)
      }
      ForEach(geometry.dividers) { divider in
        dividerView(divider)
          .workspaceCanvasFrame(divider.frame)
      }
      // While reordering in its own strip the tab itself shows the landing,
      // so neither the insertion bar nor the ghost is drawn.
      if let drag, drag.sort == nil {
        if let target = drag.target, let rect = resolver.indicator(for: target, dragging: drag.view) {
          WorkspaceDropIndicator(target: target)
            .allowsHitTesting(false)
            .workspaceCanvasFrame(rect)
        }
        WorkspaceDragGhost(title: title(drag.view))
          .frame(maxWidth: .infinity, alignment: .leading)
          .allowsHitTesting(false)
          .workspaceCanvasFrame(
            CGRect(x: drag.location.x + 10, y: drag.location.y + 8, width: WorkspaceChrome.tabMaxWidth, height: 28))
      }
    }
  }

  private func groupChrome(_ group: WorkspaceGroup, height: CGFloat, resolver: TabDropResolver) -> some View {
    VStack(spacing: 0) {
      tabStrip(group, resolver: resolver)
        .frame(height: height)
      Spacer(minLength: 0)
    }
    .glassSurface(.panel, cornerRadius: WorkspaceChrome.groupRadius)
  }

  private func tabStrip(_ group: WorkspaceGroup, resolver: TabDropResolver) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: WorkspaceChrome.tabSpacing) {
        ForEach(group.views, id: \.self) { view in
          let role = dragRole(of: view)
          WorkspaceTabButton(
            title: title(view),
            isSelected: view == group.selected,
            isInFocusedGroup: group.id == focusedGroupID,
            dragRole: role
          ) {
            select(view, in: group.id)
          }
          .offset(x: drag?.sort?.offset(of: view) ?? 0)
          .zIndex(role == .following ? 1 : 0)
          // The followed tab tracks the pointer; only its siblings slide.
          .transaction { transaction in
            if role == .following { transaction.animation = nil }
          }
          // After the offset, so the measured frame stays the laid-out slot
          // the sort and the drop resolver count from.
          .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(WorkspaceChrome.coordinateSpace))
          } action: { frame in
            tabFrames[view] = frame
          }
          .simultaneousGesture(tabDrag(view, resolver: resolver))
        }
      }
      .padding([.top, .horizontal], WorkspaceChrome.tabInset)
      .frame(maxHeight: .infinity)
    }
    .scrollIndicators(.hidden)
    // Under the tabs, so the selected tab covers it and joins the panel below.
    .background(alignment: .bottom) {
      Rectangle().fill(theme.line).frame(height: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isTabBar)
  }

  private func panelView(_ slot: PanelSlot) -> some View {
    let shape = UnevenRoundedRectangle(
      bottomLeadingRadius: WorkspaceChrome.groupRadius, bottomTrailingRadius: WorkspaceChrome.groupRadius)
    // The grid's panel padding (`GridDashboardView`), so a panel's title clears
    // the tab strip and its last row clears the rounded bottom.
    return panel(slot.id)
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .clipShape(shape)
      .opacity(slot.isSelected ? 1 : 0)
      .allowsHitTesting(slot.isSelected && drag == nil)
      // A hidden tab's panel must not take keyboard focus or be read out.
      .disabled(!slot.isSelected)
      .accessibilityHidden(!slot.isSelected)
      .simultaneousGesture(TapGesture().onEnded { focusedGroupID = slot.groupID })
  }

  private func panelSlots(_ geometry: WorkspaceGeometry) -> [PanelSlot] {
    layout.groups.flatMap { group -> [PanelSlot] in
      guard let placed = geometry.group(id: group.id) else { return [] }
      return group.views.map { view in
        PanelSlot(id: view, groupID: group.id, content: placed.content, isSelected: view == group.selected)
      }
    }
  }

  private func dividerView(_ divider: WorkspaceGeometry.Divider) -> some View {
    WorkspaceDividerHandle(
      axis: divider.axis, isActive: resize?.id == divider.id || keyboardDivider == divider.id
    )
    .gesture(dividerDrag(divider))
    .onTapGesture(count: 2) { equalize(divider) }
    .focusable()
    // The system ring drew a stray bar across the panels; the handle's own
    // accent bar shows keyboard focus instead.
    .focusEffectDisabled()
    .focused($focusedDivider, equals: divider.id)
    .onKeyPress(keys: Self.arrowKeys(divider.axis)) { press in
      keyboardDivider = divider.id
      let backwards = press.key == .leftArrow || press.key == .upArrow
      nudge(divider, by: backwards ? -Self.keyboardStep : Self.keyboardStep)
      return .handled
    }
    .accessibilityElement()
    .accessibilityLabel("Redimensionar painéis")
    .accessibilityAdjustableAction { direction in
      nudge(divider, by: direction == .increment ? Self.keyboardStep : -Self.keyboardStep)
    }
  }

  private static func arrowKeys(_ axis: WorkspaceAxis) -> Set<KeyEquivalent> {
    axis == .x ? [.leftArrow, .rightArrow] : [.upArrow, .downArrow]
  }

  /// ⌃Tab / ⌃⇧Tab, and Esc while a tab is dragged. Invisible buttons, so the
  /// shortcuts work wherever the focus is inside the window.
  private var shortcuts: some View {
    ZStack {
      Button("Próxima aba") { cycle(by: 1) }
        .keyboardShortcut(.tab, modifiers: .control)
      Button("Aba anterior") { cycle(by: -1) }
        .keyboardShortcut(.tab, modifiers: [.control, .shift])
      if drag != nil {
        Button("Cancelar") { cancelDrag() }
          .keyboardShortcut(.cancelAction)
      }
    }
    .opacity(0)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  // MARK: - Gestures

  private func tabDrag(_ view: ModuleID, resolver: TabDropResolver) -> some Gesture {
    DragGesture(minimumDistance: Self.dragThreshold, coordinateSpace: .named(WorkspaceChrome.coordinateSpace))
      .updating($tabGestureLive) { _, live, _ in live = true }
      .onChanged { value in
        guard !dragCancelled else { return }
        let next = TabDrag(
          view: view,
          location: value.location,
          target: resolver.target(at: value.location, dragging: view),
          sort: resolver.sort(
            dragging: view, at: value.location, from: value.startLocation, spacing: WorkspaceChrome.tabSpacing)
        )
        if TabDropTarget.isNewLanding(from: drag?.target, to: next.target) {
          NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        // Siblings move only when the landing slot changes or the tab enters
        // or leaves its strip; every other update just follows the pointer.
        if next.sort?.index != drag?.sort?.index {
          withAnimation(WorkspaceChrome.sortAnimation(reduceMotion: reduceMotion)) { drag = next }
        } else {
          drag = next
        }
      }
      .onEnded { value in
        let cancelled = dragCancelled
        dragCancelled = false
        guard !cancelled, let target = resolver.target(at: value.location, dragging: view) else {
          withAnimation(WorkspaceChrome.sortAnimation(reduceMotion: reduceMotion)) { drag = nil }
          return
        }
        // One transaction for the offsets and the new order: each tab slides
        // from where it is drawn to its new slot instead of snapping back first.
        withAnimation(Motion.ease(reduceMotion: reduceMotion)) {
          drag = nil
          layout = TabDropResolver.apply(target, moving: view, to: layout)
        }
        focusedGroupID = layout.group(containing: view)?.id
      }
  }

  /// Resizes from the layout as it was when the drag began, so a side that hit
  /// its minimum follows the pointer again as soon as it comes back.
  private func dividerDrag(_ divider: WorkspaceGeometry.Divider) -> some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        let origin: WorkspaceLayout
        if let resize, resize.id == divider.id {
          origin = resize.origin
        } else {
          origin = layout
          resize = DividerResize(id: divider.id, origin: layout)
          keyboardDivider = nil
        }
        guard let split = origin.split(id: divider.splitID) else { return }
        let translation = divider.axis == .x ? value.translation.width : value.translation.height
        let delta = WorkspaceGeometry.resizeDelta(translation: translation, divider: divider, weights: split.weights)
        layout = origin.resizing(split: divider.splitID, boundary: divider.boundary, by: delta)
      }
      .onEnded { _ in
        resize = nil
      }
  }

  // MARK: - Actions

  private func select(_ view: ModuleID, in groupID: String) {
    focusedGroupID = groupID
    layout = layout.selecting(view)
  }

  private func cycle(by step: Int) {
    guard
      let group = focusedGroupID.flatMap({ layout.group(id: $0) }) ?? layout.groups.first,
      let next = group.cycled(by: step)
    else { return }
    focusedGroupID = group.id
    layout = layout.selecting(next)
  }

  private func cancelDrag() {
    dragCancelled = true
    withAnimation(WorkspaceChrome.sortAnimation(reduceMotion: reduceMotion)) { drag = nil }
  }

  private func dragRole(of view: ModuleID) -> WorkspaceTabDragRole {
    guard let drag, drag.view == view else { return .none }
    return drag.sort == nil ? .leftBehind : .following
  }

  private func nudge(_ divider: WorkspaceGeometry.Divider, by step: Double) {
    guard let split = layout.split(id: divider.splitID) else { return }
    let delta = WorkspaceGeometry.resizeDelta(
      translation: CGFloat(step) * divider.length, divider: divider, weights: split.weights)
    layout = layout.resizing(split: divider.splitID, boundary: divider.boundary, by: delta)
  }

  /// Double-click on a divider, as Trellis' `equalize`.
  private func equalize(_ divider: WorkspaceGeometry.Divider) {
    guard let split = layout.split(id: divider.splitID) else { return }
    let delta = WorkspaceGeometry.equalizingDelta(divider: divider, weights: split.weights)
    layout = layout.resizing(split: divider.splitID, boundary: divider.boundary, by: delta)
  }

  /// The host reconciles too; doing it here keeps the view right before the
  /// host's first pass. Writes only on a real change, so the two never loop.
  private func reconcile() {
    let next = layout.reconciled(with: modules)
    if next != layout { layout = next }
  }
}

private struct TabDrag: Equatable {
  var view: ModuleID
  /// In the canvas' coordinate space.
  var location: CGPoint
  var target: TabDropTarget?
  /// Set while the pointer is over the tab's own strip.
  var sort: TabStripSort?
}

private struct DividerResize: Equatable {
  var id: String
  var origin: WorkspaceLayout
}

private struct PanelSlot: Identifiable {
  var id: ModuleID
  var groupID: String
  var content: CGRect
  var isSelected: Bool
}

extension WorkspaceGroup {
  /// The tab `step` places away from the selected one, wrapping at both ends
  /// (⌃Tab / ⌃⇧Tab). Nil for a group without tabs.
  nonisolated func cycled(by step: Int) -> ModuleID? {
    guard !views.isEmpty else { return nil }
    let count = views.count
    let index = views.firstIndex(of: selected) ?? 0
    return views[((index + step) % count + count) % count]
  }
}
