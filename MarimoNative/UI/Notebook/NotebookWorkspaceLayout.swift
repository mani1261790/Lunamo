import SwiftUI

/// One-way allocation: window bounds -> panel widths -> editor bounds.
/// Child fitting sizes never participate in the window's size constraints.
struct NotebookWorkspaceWidths: Equatable {
  let sidebar: CGFloat
  let editor: CGFloat
  let assistant: CGFloat

  static func resolve(
    available: CGFloat, sidebar: CGFloat?, assistant: CGFloat?
  ) -> Self {
    let width = max(0, available)
    let usable = width
    let budget = max(0, usable - 360)
    let sidebarMinimum: CGFloat = sidebar == nil ? 0 : 180
    let assistantMinimum: CGFloat = assistant == nil ? 0 : 280
    let minimum = sidebarMinimum + assistantMinimum
    // SwiftUI also proposes zero and undersized bounds while measuring.
    if budget < minimum {
      let fraction = minimum == 0 ? 0 : budget / minimum
      let left = sidebarMinimum * fraction
      let right = assistantMinimum * fraction
      return Self(sidebar: left, editor: usable - left - right, assistant: right)
    }
    let left = sidebar.map { min(max(180, $0), min(360, budget - assistantMinimum)) } ?? 0
    let right = assistant.map { min(max(280, $0), min(520, budget - left)) } ?? 0
    return Self(sidebar: left, editor: usable - left - right, assistant: right)
  }
}

struct NotebookWorkspaceLayout<Sidebar: View, Editor: View, Assistant: View>: View {
  let sidebarPresented: Bool
  let assistantPresented: Bool
  @ViewBuilder var sidebar: () -> Sidebar
  @ViewBuilder var editor: () -> Editor
  @ViewBuilder var assistant: () -> Assistant
  @State private var sidebarWidth: CGFloat = 240
  @State private var assistantWidth: CGFloat = 320

  var body: some View {
    GeometryReader { geometry in
      let widths = NotebookWorkspaceWidths.resolve(
        available: geometry.size.width,
        sidebar: sidebarPresented ? sidebarWidth : nil,
        assistant: assistantPresented ? assistantWidth : nil
      )
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) {
          if sidebarPresented {
            sidebar()
              .frame(width: widths.sidebar, height: geometry.size.height)
              .clipped()
          }
          editor()
            .frame(width: widths.editor, height: geometry.size.height)
            .clipped()
          if assistantPresented {
            assistant()
              .frame(width: widths.assistant, height: geometry.size.height)
              .clipped()
          }
        }
        if sidebarPresented {
          NotebookPanelDivider(label: "Resize Sidebar", value: widths.sidebar) { proposed in
            sidebarWidth =
              NotebookWorkspaceWidths.resolve(
                available: geometry.size.width, sidebar: proposed,
                assistant: assistantPresented ? assistantWidth : nil
              ).sidebar
          }
          .frame(height: geometry.size.height)
          .offset(x: widths.sidebar - NotebookResizeHandle.thickness / 2)
        }
        if assistantPresented {
          NotebookPanelDivider(label: "Resize Assistant", value: widths.assistant, direction: -1) {
            proposed in
            assistantWidth =
              NotebookWorkspaceWidths.resolve(
                available: geometry.size.width, sidebar: sidebarPresented ? sidebarWidth : nil,
                assistant: proposed
              ).assistant
          }
          .frame(height: geometry.size.height)
          .offset(x: widths.sidebar + widths.editor - NotebookResizeHandle.thickness / 2)
        }
      }
    }
  }
}

private struct NotebookPanelDivider: View {
  let label: String
  let value: CGFloat
  var direction: CGFloat = 1
  let resize: (CGFloat) -> Void

  var body: some View {
    NotebookResizeHandle(horizontal: true, value: value, direction: direction, resize: resize)
      .frame(width: NotebookResizeHandle.thickness)
      .accessibilityLabel(localizedUI(label))
      .accessibilityValue("\(Int(value))")
      .accessibilityAdjustableAction { action in
        resize(value + (action == .increment ? 20 : -20))
      }
      .zIndex(1)
  }
}
