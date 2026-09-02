import MarimoApplication
import MarimoDomain
import SwiftUI

public struct CellView: View {
  private let cell: NotebookCellState
  private let selected: Bool
  private let send: (NotebookIntent) -> Void

  public init(
    cell: NotebookCellState,
    selected: Bool,
    send: @escaping (NotebookIntent) -> Void
  ) {
    self.cell = cell
    self.selected = selected
    self.send = send
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(cell.name)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
      Text(cell.code.isEmpty ? "Empty Python cell" : cell.code)
        .font(.body.monospaced())
        .foregroundStyle(cell.code.isEmpty ? .secondary : .primary)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .accessibilityLabel("Python code editor placeholder")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .leading) {
      if selected {
        Rectangle()
          .fill(Color.accentColor)
          .frame(width: 3)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      send(.selectCell(cell.runtimeID))
    }
  }
}
