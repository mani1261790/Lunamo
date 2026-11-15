import SwiftUI

// Apply native styles to the original button, without nesting Button(configuration).
struct CellExecutionButtonStyle: ViewModifier {
  let prominent: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if prominent {
      content
        .buttonStyle(.glassProminent)
        .tint(.accentColor)
    } else {
      content
        .buttonStyle(.bordered)
    }
  }
}
