import AppKit
import SwiftUI

struct NotebookResizeHandle: NSViewRepresentable {
  nonisolated static let thickness: CGFloat = 9
  let horizontal: Bool
  let value: CGFloat
  var direction: CGFloat = 1
  let resize: (CGFloat) -> Void

  func makeNSView(context: Context) -> NotebookResizeHandleView {
    let view = NotebookResizeHandleView()
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: NotebookResizeHandleView, context: Context) {
    view.horizontal = horizontal
    view.value = value
    view.direction = direction
    view.resize = resize
  }
}

/// A real hit region, rather than an overlay extending beyond a one-point view.
final class NotebookResizeHandleView: NSView {
  var horizontal = true
  var value: CGFloat = 0
  var direction: CGFloat = 1
  var resize: (CGFloat) -> Void = { _ in }
  private var dragStart: (point: NSPoint, value: CGFloat)?

  override var acceptsFirstResponder: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: horizontal ? .resizeLeftRight : .resizeUpDown)
  }

  override func mouseDown(with event: NSEvent) {
    guard let window else { return }
    dragStart = (window.convertPoint(toScreen: event.locationInWindow), value)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let window, let dragStart else { return }
    let point = window.convertPoint(toScreen: event.locationInWindow)
    // Screen Y grows upward, matching the terminal's height direction.
    let delta = horizontal ? point.x - dragStart.point.x : point.y - dragStart.point.y
    resize(dragStart.value + direction * delta)
  }

  override func mouseUp(with event: NSEvent) {
    dragStart = nil
  }
}
