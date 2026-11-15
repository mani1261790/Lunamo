import SwiftUI

/// Quiet, consistently sized controls for the assistant's header and composer.
struct AssistantControlStyle: ButtonStyle {
  var prominent = false

  func makeBody(configuration: Configuration) -> some View {
    Control(configuration: configuration, prominent: prominent)
  }

  private struct Control: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 8)
        .frame(minWidth: 32, minHeight: 32)
        .foregroundStyle(prominent && enabled ? Color.white : Color.primary)
        .background {
          RoundedRectangle(cornerRadius: prominent ? 16 : 10, style: .continuous)
            .fill(
              prominent && enabled
                ? Color.accentColor
                : Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0.025))
        }
        .opacity(enabled ? 1 : 0.4)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }
  }
}
