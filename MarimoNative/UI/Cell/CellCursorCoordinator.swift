import AppKit

/// Coalesces hover changes from a layout pass before touching AppKit's cursor stack.
@MainActor
final class CellCursorCoordinator {
  enum Style: Equatable {
    case grab, pointer, dragging
  }

  static let shared = CellCursorCoordinator()
  private var requests: [(UUID, Style)] = []
  private var applied: Style?
  private var scheduled = false
  private let scheduleAutomatically: Bool
  private let transition: @MainActor (Style?, Style?) -> Void

  init(
    scheduleAutomatically: Bool = true,
    transition: @escaping @MainActor (Style?, Style?) -> Void = CellCursorCoordinator.applyNative
  ) {
    self.scheduleAutomatically = scheduleAutomatically
    self.transition = transition
  }

  func request(_ style: Style?, owner: UUID) {
    requests.removeAll { $0.0 == owner }
    if let style { requests.append((owner, style)) }
    guard scheduleAutomatically, !scheduled else { return }
    scheduled = true
    Task { @MainActor [weak self] in self?.flush() }
  }

  func flush() {
    scheduled = false
    let next = requests.contains { $0.1 == .dragging } ? Style.dragging : requests.last?.1
    guard next != applied else { return }
    transition(applied, next)
    applied = next
  }

  private static func applyNative(previous: Style?, next: Style?) {
    if previous != nil { NSCursor.pop() }
    switch next {
    case .grab: NSCursor.openHand.push()
    case .pointer: NSCursor.pointingHand.push()
    case .dragging: NSCursor.closedHand.push()
    case nil: break
    }
  }
}
