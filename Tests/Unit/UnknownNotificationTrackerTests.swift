import MarimoBackend
import MarimoDomain
import MarimoProtocol
import Testing

@Suite("Unknown notification logging")
struct UnknownNotificationTrackerTests {
  @Test("Individual logging stops after 100 occurrences per session and operation")
  func suppressesAfterOneHundred() async {
    let tracker = UnknownNotificationTracker()
    let notification = MarimoNotification.unknown(
      operation: "future-op",
      payload: ["value": .integer(1)]
    )
    for _ in 1...100 {
      #expect(await tracker.record(sessionID: "session-a", notification: notification))
    }
    #expect(!(await tracker.record(sessionID: "session-a", notification: notification)))
    #expect(await tracker.count(sessionID: "session-a", operation: "future-op") == 101)
    #expect(await tracker.record(sessionID: "session-b", notification: notification))
  }
}
