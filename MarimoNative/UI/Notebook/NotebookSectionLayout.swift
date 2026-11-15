import Foundation
import MarimoDomain

struct NotebookSectionRow: Identifiable {
  let index: Int
  let cell: NotebookCellState
  let headingLevel: Int?

  var id: UUID { cell.runtimeID }
}

enum NotebookSectionLayout {
  static func visibleRows(
    cells: [NotebookCellState],
    collapsedHeadingCellIDs: Set<UUID>
  ) -> [NotebookSectionRow] {
    var rows: [NotebookSectionRow] = []
    var collapsedAncestorLevels: [Int] = []

    for (index, cell) in cells.enumerated() {
      let headingLevel = cell.editor.markdown.flatMap(MarkdownDocumentParser.leadingHeadingLevel)

      if let headingLevel {
        while let ancestorLevel = collapsedAncestorLevels.last,
          ancestorLevel >= headingLevel
        {
          collapsedAncestorLevels.removeLast()
        }
      }

      if collapsedAncestorLevels.isEmpty {
        rows.append(NotebookSectionRow(index: index, cell: cell, headingLevel: headingLevel))
      }

      if let headingLevel, collapsedHeadingCellIDs.contains(cell.runtimeID) {
        collapsedAncestorLevels.append(headingLevel)
      }
    }

    return rows
  }
}
