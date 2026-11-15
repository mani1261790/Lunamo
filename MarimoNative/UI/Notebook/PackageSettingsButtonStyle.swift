import SwiftUI

struct PackageSettingsButtonStyle: ButtonStyle {
  var prominent = false
  var iconOnly = false

  func makeBody(configuration: Configuration) -> some View {
    Control(configuration: configuration, prominent: prominent, iconOnly: iconOnly)
  }

  private struct Control: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    let iconOnly: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .font(.callout.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, iconOnly ? 0 : 14)
        .frame(width: iconOnly ? 30 : nil, height: 30)
        .foregroundStyle(prominent && enabled ? Color.white : Color.primary)
        .background {
          Capsule(style: .continuous)
            .fill(backgroundColor)
        }
        .overlay {
          if !prominent {
            Capsule(style: .continuous)
              .strokeBorder(Color.primary.opacity(hovering ? 0.2 : 0.08), lineWidth: 1)
          }
        }
        .contentShape(Capsule(style: .continuous))
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
      if prominent && enabled {
        return Color.accentColor.opacity(configuration.isPressed ? 0.76 : hovering ? 0.9 : 0.82)
      }
      return Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.09 : 0.045)
    }
  }
}
