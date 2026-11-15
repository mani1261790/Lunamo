import SwiftUI
import Testing

@testable import MarimoUI

@MainActor
@Suite("Terminal split sizing")
struct NotebookTerminalSplitTests {
  private typealias Split = NotebookTerminalSplit<EmptyView, EmptyView>

  @Test("A small layout proposal never produces a negative terminal frame")
  func smallProposals() {
    for available in [0.0, 100, 320, 400, 480] {
      let height = Split.terminalHeight(available: available, requested: 240)
      #expect(height >= 0)
      #expect(height <= max(0, available - 320))
    }
  }

  @Test("Dragging respects both the terminal limits and space for the notebook")
  func dragLimits() {
    for available in [640.0, 800, 1200] {
      for requested in [-1000.0, 160, 240, 420, 10000] {
        let height = Split.terminalHeight(available: available, requested: requested)
        #expect(height >= 160)
        #expect(height <= 420)
        #expect(available - height >= 320)
      }
    }
  }

  @Test("Resizing back restores the user's requested height")
  func restoredHeight() {
    let requested: CGFloat = 380
    #expect(Split.terminalHeight(available: 640, requested: requested) < requested)
    #expect(Split.terminalHeight(available: 900, requested: requested) == requested)
  }
}
