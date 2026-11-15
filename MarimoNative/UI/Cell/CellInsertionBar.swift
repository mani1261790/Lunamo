import SwiftUI

public struct CellInsertionBar: View {
  private let position: Int
  private let insertCode: @MainActor @Sendable () -> Void
  private let insertText: @MainActor @Sendable () -> Void
  private let reorderTargeted: Bool
  @State private var hovering = false

  public init(
    position: Int,
    insertCode: @escaping @MainActor @Sendable () -> Void,
    insertText: @escaping @MainActor @Sendable () -> Void,
    reorderTargeted: Bool = false
  ) {
    self.position = position
    self.insertCode = insertCode
    self.insertText = insertText
    self.reorderTargeted = reorderTargeted
  }

  public var body: some View {
    ZStack {
      Color.clear

      HStack(spacing: 10) {
        insertionLine(fadesTowardLeadingEdge: true)
        if reorderTargeted {
          Label("Move Here", systemImage: "arrow.down.to.line.compact")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
          Button(action: insertCode) {
            Label {
              Text(localizedUI("Code"))
            } icon: {
              Image(systemName: "plus")
            }
          }
          .buttonStyle(CellInsertionButtonStyle())
          .help(localizedUI("Insert Code Cell"))
          .accessibilityLabel(localizedUI("Insert Code Cell"))

          Button(action: insertText) {
            Label {
              Text(localizedUI("Text"))
            } icon: {
              Image(systemName: "plus")
            }
          }
          .buttonStyle(CellInsertionButtonStyle())
          .help(localizedUI("Insert Text Cell"))
          .accessibilityLabel(localizedUI("Insert Text Cell"))
        }
        insertionLine(fadesTowardLeadingEdge: false)
      }
      .opacity(hovering || reorderTargeted ? 1 : 0)
      .allowsHitTesting(hovering || reorderTargeted)
    }
    .frame(height: reorderTargeted ? 44 : 20)
    .background(
      reorderTargeted ? Color.accentColor.opacity(0.1) : .clear,
      in: RoundedRectangle(cornerRadius: 10)
    )
    .padding(.leading, 54)
    .contentShape(Rectangle())
    .onContinuousHover { phase in
      switch phase {
      case .active:
        hovering = true
      case .ended:
        hovering = false
      }
    }
    .animation(.snappy(duration: 0.18), value: reorderTargeted)
    .animation(.easeOut(duration: 0.14), value: hovering)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(localizedUI("Cell insertion position %ld", position + 1))
  }

  private func insertionLine(fadesTowardLeadingEdge: Bool) -> some View {
    Rectangle()
      .fill(
        LinearGradient(
          colors: [
            (reorderTargeted ? Color.accentColor : Color(nsColor: .separatorColor)).opacity(
              fadesTowardLeadingEdge ? 0 : 1),
            (reorderTargeted ? Color.accentColor : Color(nsColor: .separatorColor)).opacity(
              fadesTowardLeadingEdge ? 1 : 0),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .frame(height: reorderTargeted ? 2 : 1)
      .animation(.easeOut(duration: 0.15), value: reorderTargeted)
      .accessibilityHidden(true)
  }
}

private struct CellInsertionButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    Control(configuration: configuration)
  }

  private struct Control: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .font(.system(size: 12, weight: .semibold))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .background {
          Capsule(style: .continuous)
            .fill(
              Color.accentColor.opacity(
                configuration.isPressed ? 0.2 : hovering ? 0.13 : 0.07
              )
            )
        }
        .overlay {
          Capsule(style: .continuous)
            .stroke(
              Color.accentColor.opacity(hovering ? 0.42 : 0.24),
              lineWidth: 1
            )
        }
        .contentShape(Capsule(style: .continuous))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
  }
}
