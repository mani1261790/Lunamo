public enum ExecutionStatus: String, Codable, Sendable, Equatable {
  case idle
  case queued
  case running
  case error
  case disabledTransitively = "disabled-transitively"
}

public enum BackendStatus: Sendable, Equatable {
  case unavailable
  case ready
}
