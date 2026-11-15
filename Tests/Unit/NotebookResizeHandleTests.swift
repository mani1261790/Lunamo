import AppKit
import SwiftUI
import Testing

@testable import MarimoUI

@MainActor
@Suite("Native panel resize handle", .serialized)
struct NotebookResizeHandleTests {
  @Test("Invisible resize regions overlap the panel edges without layout gutters")
  func workspaceHitRegions() async throws {
    let workspace = NotebookWorkspaceLayout(sidebarPresented: true, assistantPresented: true) {
      Color.gray
    } editor: {
      Color.black
    } assistant: {
      Color.gray
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1320, height: 800),
      styleMask: [.borderless], backing: .buffered, defer: false)
    let container = try #require(window.contentView)
    let hosting = NSHostingView(rootView: workspace)
    hosting.sizingOptions = []
    hosting.frame = NSRect(x: 0, y: 0, width: 1320, height: 800)
    container.addSubview(hosting)
    hosting.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(50))
    hosting.layoutSubtreeIfNeeded()
    func handles(_ view: NSView) -> [NotebookResizeHandleView] {
      (view as? NotebookResizeHandleView).map { [$0] }
        ?? view.subviews.flatMap { handles($0) }
    }
    let regions = handles(hosting)
    #expect(regions.count == 2)
    let centers = regions.map {
      $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: hosting).x
    }.sorted()
    #expect(abs(centers[0] - 240) <= 0.5)
    #expect(abs(centers[1] - 1000) <= 0.5)
    for region in regions {
      #expect(region.bounds.width == 9)
      for x in [CGFloat(1), 4.5, 8] {
        let point = region.convert(NSPoint(x: x, y: 300), to: container)
        #expect(container.hitTest(point) === region)
      }
    }
  }

  @Test("Drag remains anchored while the divider frame moves")
  func movingDivider() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 960, height: 640),
      styleMask: [.borderless], backing: .buffered, defer: false)
    let view = NotebookResizeHandleView(frame: NSRect(x: 240, y: 0, width: 9, height: 640))
    window.contentView!.addSubview(view)
    view.value = 240
    var values: [CGFloat] = []
    view.resize = { values.append($0) }
    func event(_ type: NSEvent.EventType, x: CGFloat) throws -> NSEvent {
      try #require(
        NSEvent.mouseEvent(
          with: type, location: NSPoint(x: x, y: 100),
          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
          context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    view.mouseDown(with: try event(.leftMouseDown, x: 244))
    view.mouseDragged(with: try event(.leftMouseDragged, x: 284))
    view.setFrameOrigin(NSPoint(x: 280, y: 0))
    view.value = 280
    view.mouseDragged(with: try event(.leftMouseDragged, x: 304))
    #expect(values == [280, 300])
    view.mouseUp(with: try event(.leftMouseUp, x: 304))
    view.mouseDragged(with: try event(.leftMouseDragged, x: 400))
    #expect(values.count == 2)
  }

  @Test("Assistant dragging left increases its width")
  func assistantDirection() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
      styleMask: [.borderless], backing: .buffered, defer: false)
    let view = NotebookResizeHandleView(frame: NSRect(x: 600, y: 0, width: 9, height: 640))
    window.contentView!.addSubview(view)
    view.value = 320
    view.direction = -1
    var result: CGFloat = 0
    view.resize = { result = $0 }
    for (type, x) in [(NSEvent.EventType.leftMouseDown, 604.0), (.leftMouseDragged, 564.0)] {
      let event = try #require(
        NSEvent.mouseEvent(
          with: type, location: NSPoint(x: x, y: 100),
          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
          context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      if type == .leftMouseDown {
        view.mouseDown(with: event)
      } else {
        view.mouseDragged(with: event)
      }
    }
    #expect(result == 360)
  }
}
