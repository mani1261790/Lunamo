import Foundation

extension NotebookStore {
  func restoreTextCellProjections() async {
    for revision in markdownRevisions.values {
      pendingTextSynchronizations.removeValue(forKey: revision)
    }
    markdownRevisions.removeAll()
    let documentID = document.documentID
    for cell in document.cells {
      let projection = try? await backend.textCell(source: cell.code, markdown: nil)
      guard document.documentID == documentID else { return }
      guard
        let index = document.cells.firstIndex(where: {
          $0.runtimeID == cell.runtimeID && $0.code == cell.code
        })
      else { continue }
      document.cells[index].editor.markdown = projection?.markdown
    }
  }
}
