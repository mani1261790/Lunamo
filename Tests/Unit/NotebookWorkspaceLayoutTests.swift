import Foundation
import Testing

@testable import MarimoUI

@Suite("Workspace width allocation")
struct NotebookWorkspaceLayoutTests {
  @Test("All panel combinations fit without negative dimensions")
  func proposedSizes() {
    let requests: [CGFloat?] = [nil, -100, 0, 180, 240, 320, 520, 10000]
    for available: CGFloat in [0, 1, 100, 460, 640, 960, 1320, 1920] {
      for sidebar in requests {
        for assistant in requests {
          let result = NotebookWorkspaceWidths.resolve(
            available: available, sidebar: sidebar, assistant: assistant)
          #expect(result.sidebar >= 0)
          #expect(result.assistant >= 0)
          #expect(result.editor >= 0)
          #expect(
            abs(result.sidebar + result.editor + result.assistant - available)
              < 0.001)
          if available >= 960 { #expect(result.editor >= 360) }
          if sidebar == nil { #expect(result.sidebar == 0) }
          if assistant == nil { #expect(result.assistant == 0) }
        }
      }
    }
  }

  @Test("At the minimum window width both panels retain usable widths")
  func minimumWindow() {
    let widths = NotebookWorkspaceWidths.resolve(available: 960, sidebar: 360, assistant: 520)
    #expect(widths.sidebar >= 180)
    #expect(widths.sidebar <= 360)
    #expect(widths.assistant >= 280)
    #expect(widths.assistant <= 520)
    #expect(widths.editor >= 360)
  }

  @Test("Closing a panel releases its space without changing the other request")
  func visibility() {
    let both = NotebookWorkspaceWidths.resolve(available: 1320, sidebar: 240, assistant: 320)
    let withoutSidebar = NotebookWorkspaceWidths.resolve(
      available: 1320, sidebar: nil, assistant: 320)
    #expect(withoutSidebar.assistant == both.assistant)
    #expect(withoutSidebar.editor == both.editor + both.sidebar)
    let withoutAssistant = NotebookWorkspaceWidths.resolve(
      available: 1320, sidebar: 240, assistant: nil)
    #expect(withoutAssistant.sidebar == both.sidebar)
    #expect(withoutAssistant.editor == both.editor + both.assistant)
  }
}
