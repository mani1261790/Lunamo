import SwiftUI

public struct CellInsertionBar: View {
  private let position: Int
  private let insertCode: @MainActor @Sendable () -> Void
  private let moveCell: @MainActor @Sendable (UUID, Int) -> Void
  @State private var hovering = false
  @State private var dropTargeted = false

  public init(
    position: Int,
    insertCode: @escaping @MainActor @Sendable () -> Void,
    moveCell: @escaping @MainActor @Sendable (UUID, Int) -> Void
  ) {
    self.position = position
    self.insertCode = insertCode
    self.moveCell = moveCell
  }

  public var body: some View {
    HStack(spacing: 8) {
      insertionLine
      Button(action: insertCode) {
        Label("Code", systemImage: "plus")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .help("Insert Code Cell")
      .accessibilityLabel("Insert Code Cell")
      insertionLine
    }
    .frame(height: 28)
    .padding(.leading, 54)
    .opacity(hovering || dropTargeted ? 1 : 0.62)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .dropDestination(for: String.self) { values, _ in
      guard let rawID = values.first, let cellID = UUID(uuidString: rawID) else { return false }
      moveCell(cellID, position)
      return true
    } isTargeted: {
      dropTargeted = $0
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(localizedUI("Cell insertion position %ld", position + 1))
  }

  private var insertionLine: some View {
    Rectangle()
      .fill(dropTargeted ? Color.accentColor : Color(nsColor: .separatorColor))
      .frame(height: dropTargeted ? 2 : 1)
      .animation(.easeOut(duration: 0.15), value: dropTargeted)
      .accessibilityHidden(true)
  }
}
