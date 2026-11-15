import SwiftUI

/// Keeps the terminal's size independent of AppKit split-child fitting sizes.
/// Nesting VSplitView inside the inspector can otherwise feed changing fitting
/// constraints back into the window during the inspector's collapse animation.
struct NotebookTerminalSplit<Canvas: View, Terminal: View>: View {
  @ViewBuilder var canvas: () -> Canvas
  @ViewBuilder var terminal: () -> Terminal
  @State private var requestedHeight: CGFloat = 240

  var body: some View {
    GeometryReader { geometry in
      let height = Self.terminalHeight(available: geometry.size.height, requested: requestedHeight)
      ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
          canvas()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          terminal()
            .frame(height: height)
            .clipped()
        }
        NotebookResizeHandle(horizontal: false, value: height) { proposed in
          requestedHeight = Self.terminalHeight(
            available: geometry.size.height, requested: proposed)
        }
        .frame(width: geometry.size.width, height: NotebookResizeHandle.thickness)
        .accessibilityLabel(localizedUI("Resize Terminal"))
        .accessibilityValue("\(Int(height))")
        .accessibilityAdjustableAction { direction in
          requestedHeight = Self.terminalHeight(
            available: geometry.size.height,
            requested: height + (direction == .increment ? 20 : -20)
          )
        }
        .offset(y: geometry.size.height - height - NotebookResizeHandle.thickness / 2)
        .zIndex(1)
      }
    }
  }

  static func terminalHeight(available: CGFloat, requested: CGFloat) -> CGFloat {
    let upper = max(0, min(420, available - 320))
    let lower = min(160, upper)
    return min(upper, max(lower, requested))
  }
}
