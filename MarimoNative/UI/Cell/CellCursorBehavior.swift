import AppKit

extension CellView {
  func updateReorderCursor(active: Bool) {
    reorderCursorActive = active
    updateHoverCursor()
  }

  func updateHoverCursor() {
    let style: CellCursorCoordinator.Style?
    if reorderCursorActive {
      style = .dragging
    } else if actionControlsHovered {
      style = .pointer
    } else if cellHovered && !editorHovered {
      style = .grab
    } else {
      style = nil
    }
    CellCursorCoordinator.shared.request(style, owner: cursorOwner)
  }

  func restoreHoverCursor() {
    CellCursorCoordinator.shared.request(nil, owner: cursorOwner)
  }

  func restoreReorderCursor() {
    reorderCursorActive = false
    restoreHoverCursor()
  }
}
