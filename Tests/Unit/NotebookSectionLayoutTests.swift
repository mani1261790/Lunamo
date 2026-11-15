import MarimoDomain
import Testing

@testable import MarimoUI

@Suite("Notebook heading sections")
struct NotebookSectionLayoutTests {
  @Test("Only a leading ATX heading starts a notebook section")
  func leadingHeadingDetection() {
    #expect(MarkdownDocumentParser.leadingHeadingLevel("# Title") == 1)
    #expect(MarkdownDocumentParser.leadingHeadingLevel("\n  ## Details\nBody") == 2)
    #expect(MarkdownDocumentParser.leadingHeadingLevel("###### Small") == 6)
    #expect(MarkdownDocumentParser.leadingHeadingLevel("#NoSpace") == nil)
    #expect(MarkdownDocumentParser.leadingHeadingLevel("Intro\n# Later") == nil)
  }

  @Test("A collapsed heading hides cells through the next same or higher heading")
  func collapsedSectionBoundary() {
    let cells = [
      textCell("# First"), codeCell("first = 1"), textCell("## Child"),
      codeCell("child = 2"), textCell("# Second"), codeCell("second = 3"),
    ]

    let rows = NotebookSectionLayout.visibleRows(
      cells: cells,
      collapsedHeadingCellIDs: [cells[0].runtimeID]
    )

    #expect(rows.map(\.index) == [0, 4, 5])
  }

  @Test("Nested section state remains independent")
  func nestedSectionState() {
    let cells = [
      textCell("# Parent"), codeCell("parent = 1"), textCell("## First child"),
      codeCell("first = 2"), textCell("## Second child"), codeCell("second = 3"),
      textCell("# Next"),
    ]

    let rows = NotebookSectionLayout.visibleRows(
      cells: cells,
      collapsedHeadingCellIDs: [cells[2].runtimeID]
    )
    #expect(rows.map(\.index) == [0, 1, 2, 4, 5, 6])

    let parentRows = NotebookSectionLayout.visibleRows(
      cells: cells,
      collapsedHeadingCellIDs: [cells[0].runtimeID, cells[2].runtimeID]
    )
    #expect(parentRows.map(\.index) == [0, 6])
  }

  private func textCell(_ markdown: String) -> NotebookCellState {
    var cell = NotebookCellState()
    cell.editor.markdown = markdown
    return cell
  }

  private func codeCell(_ code: String) -> NotebookCellState {
    NotebookCellState(code: code)
  }
}
