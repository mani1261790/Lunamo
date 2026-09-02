import Foundation

public enum ExternalFileState: Sendable, Equatable {
  case none
  case changed(URL, localDirty: Bool)
  case recovery(url: URL, source: String, code: String, cause: String)
  case deleted(URL)
}

public struct NotebookUserFacingError: Identifiable, Sendable, Equatable {
  public enum Code: String, Sendable, Equatable {
    case lspStart = "MN-LSP-START-001"
    case lspProtocol = "MN-LSP-PROTOCOL-002"
    case lspTimeout = "MN-LSP-TIMEOUT-003"
    case documentUTF8 = "MN-DOC-UTF8-101"
    case documentSyntax = "MN-DOC-SYNTAX-102"
    case documentConvert = "MN-DOC-CONVERT-103"
    case documentSave = "MN-DOC-SAVE-104"
    case documentConflict = "MN-DOC-CONFLICT-105"
    case environmentNotFound = "MN-ENV-NOTFOUND-201"
    case environmentPreflight = "MN-ENV-PREFLIGHT-202"
    case environmentMarimo = "MN-ENV-MARIMO-203"
    case kernelStart = "MN-KERNEL-START-301"
    case kernelCrash = "MN-KERNEL-CRASH-302"
    case kernelInterrupt = "MN-KERNEL-INTERRUPT-303"
    case outputDecode = "MN-OUTPUT-DECODE-401"
    case outputSize = "MN-OUTPUT-SIZE-402"
    case widgetDecode = "MN-WIDGET-DECODE-501"
    case webCrash = "MN-WEB-CRASH-601"
  }

  public let id = UUID()
  public let code: Code
  public let cause: String
  public let target: String
  public let recoveryActions: [String]

  public init(code: Code, cause: String, target: String, recoveryActions: [String]) {
    self.code = code
    self.cause = cause
    self.target = target
    self.recoveryActions = recoveryActions
  }
}
