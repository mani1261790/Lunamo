import Foundation
import Testing

@testable import MarimoUI

@MainActor
@Suite("Cell cursor ownership")
struct CellCursorCoordinatorTests {
  @Test("Crossing many cells in one layout does not regenerate the same cursor")
  func coalescesCellCrossings() {
    var changes: [CellCursorCoordinator.Style?] = []
    let coordinator = CellCursorCoordinator(scheduleAutomatically: false) { _, next in
      changes.append(next)
    }
    var owner = UUID()
    coordinator.request(.grab, owner: owner)
    coordinator.flush()
    for _ in 0..<100 {
      coordinator.request(nil, owner: owner)
      owner = UUID()
      coordinator.request(.grab, owner: owner)
    }
    coordinator.flush()
    #expect(changes == [.grab])
    coordinator.request(nil, owner: owner)
    coordinator.flush()
    #expect(changes == [.grab, nil])
  }

  @Test("A late exit from another cell cannot remove the current pointer")
  func independentOwners() {
    var changes: [CellCursorCoordinator.Style?] = []
    let coordinator = CellCursorCoordinator(scheduleAutomatically: false) { _, next in
      changes.append(next)
    }
    let old = UUID()
    let current = UUID()
    coordinator.request(.grab, owner: old)
    coordinator.flush()
    coordinator.request(.pointer, owner: current)
    coordinator.request(nil, owner: old)
    coordinator.flush()
    #expect(changes == [.grab, .pointer])
    coordinator.request(nil, owner: current)
    coordinator.flush()
    #expect(changes == [.grab, .pointer, nil])
  }

  @Test("Dragging takes precedence and releases back to the hovered control")
  func draggingPriority() {
    var changes: [CellCursorCoordinator.Style?] = []
    let coordinator = CellCursorCoordinator(scheduleAutomatically: false) { _, next in
      changes.append(next)
    }
    let drag = UUID()
    let control = UUID()
    coordinator.request(.dragging, owner: drag)
    coordinator.flush()
    coordinator.request(.pointer, owner: control)
    coordinator.flush()
    #expect(changes == [.dragging])
    coordinator.request(nil, owner: drag)
    coordinator.flush()
    #expect(changes == [.dragging, .pointer])
    coordinator.request(nil, owner: control)
    coordinator.flush()
    #expect(changes == [.dragging, .pointer, nil])
  }
}
