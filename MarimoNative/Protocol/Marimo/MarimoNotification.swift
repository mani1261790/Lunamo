import MarimoDomain

public enum KnownNotificationOperation: String, Codable, Sendable, Equatable, CaseIterable {
  case kernelReady = "kernel-ready"
  case cellOperation = "cell-op"
  case completedRun = "completed-run"
  case interrupted
  case kernelStartupError = "kernel-startup-error"
  case variables
  case variableValues = "variable-values"
  case removeUIElements = "remove-ui-elements"
  case sendUIElementMessage = "send-ui-element-message"
  case modelLifecycle = "model-lifecycle"
  case functionCallResult = "function-call-result"
  case alert, banner
  case missingPackageAlert = "missing-package-alert"
  case installingPackageAlert = "installing-package-alert"
  case startupLogs = "startup-logs"
  case focusCell = "focus-cell"
  case activeLine = "active-line"
  case consumerCapabilities = "consumer-capabilities"
}

public enum MarimoNotification: Codable, Sendable, Equatable {
  case known(KnownNotificationOperation, payload: [String: JSONValue])
  case unknown(operation: String, payload: [String: JSONValue])

  public init(from decoder: Decoder) throws {
    var object = try [String: JSONValue](from: decoder)
    guard case .string(let operation)? = object.removeValue(forKey: "op") else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Notification op is required"))
    }
    if let known = KnownNotificationOperation(rawValue: operation) {
      self = .known(known, payload: object)
    } else {
      self = .unknown(operation: operation, payload: object)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var object: [String: JSONValue]
    switch self {
    case .known(let operation, let payload):
      object = payload
      object["op"] = .string(operation.rawValue)
    case .unknown(let operation, let payload):
      object = payload
      object["op"] = .string(operation)
    }
    try object.encode(to: encoder)
  }
}

public struct KernelNotificationEnvelope: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let sessionID: String
  public let notification: MarimoNotification
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case sessionID = "sessionId"
    case notification
  }
  public init(notebookURI: String, sessionID: String, notification: MarimoNotification) {
    self.notebookURI = notebookURI
    self.sessionID = sessionID
    self.notification = notification
  }
}
