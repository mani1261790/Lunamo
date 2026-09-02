public enum ExecutionStatus: String, Codable, Sendable, Equatable {
  case idle
  case queued
  case running
  case disabledTransitively = "disabled-transitively"
}

public enum BackendStatus: Sendable, Equatable {
  case unavailable
  case ready
}
