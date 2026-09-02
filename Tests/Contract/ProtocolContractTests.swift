import Foundation
import MarimoDomain
import MarimoProtocol
import Testing

@Suite("Pinned protocol contract")
struct ProtocolContractTests {
  @Test("Every MVP command fixture decodes and re-encodes without unknown fields")
  func commandFixturesRoundTrip() throws {
    let data = try Data(contentsOf: fixture("command_protocol_mvp.json"))
    let commands = try JSONDecoder().decode([MarimoCommand].self, from: data)
    let fixtures = try JSONDecoder().decode([[String: JSONValue]].self, from: data)
    #expect(commands.count == 17)

    for (command, fixture) in zip(commands, fixtures) {
      let encoded = try JSONEncoder().encode(command)
      let object = try JSONDecoder().decode([String: JSONValue].self, from: encoded)
      guard case .string(let kind)? = object["kind"] else {
        Issue.record("Encoded command has no kind")
        continue
      }
      let allowed = allowedKeys[kind] ?? []
      #expect(Set(object.keys).isSubset(of: allowed), "Unexpected key in \(kind)")
      #expect(requiredKeys[kind, default: []].isSubset(of: Set(object.keys)))
      #expect(fixture["kind"] == object["kind"])
    }
  }

  @Test("Owned document rejects versions other than one")
  func invalidOwnedDocumentVersion() {
    let data = Data(#"{"version":"2","metadata":{},"cells":[]}"#.utf8)
    #expect(throws: OwnedNotebookDocumentError.unsupportedVersion("2")) {
      try JSONDecoder().decode(OwnedNotebookDocumentV1.self, from: data)
    }
  }

  @Test("Owned document preserves unknown metadata and passthrough")
  func ownedDocumentPreservesOpaqueValues() throws {
    let data = try Data(contentsOf: fixture("command_protocol_mvp.json"))
    let commands = try JSONDecoder().decode([MarimoCommand].self, from: data)
    guard case .printNotebook(let document) = commands[10] else {
      Issue.record("Expected print-notebook fixture")
      return
    }
    #expect(document.metadata["future"] == .object(["kept": .bool(true)]))
    #expect(document.appOptions.passthrough["width"] == .string("full"))
  }

  @Test("All required notification operations decode through the pinned envelope")
  func notificationFixturesDecode() throws {
    let data = try Data(contentsOf: fixture("kernel_notifications_mvp.json"))
    let envelopes = try JSONDecoder().decode([KernelNotificationEnvelope].self, from: data)
    let known = envelopes.compactMap { envelope -> KnownNotificationOperation? in
      guard case .known(let operation, _) = envelope.notification else { return nil }
      return operation
    }
    #expect(Set(known) == Set(KnownNotificationOperation.allCases))
  }

  @Test("Unknown notification operation remains lossless")
  func unknownNotificationIsPreserved() throws {
    let data = Data(#"{"op":"future-op","future_key":{"value":7}}"#.utf8)
    let notification = try JSONDecoder().decode(MarimoNotification.self, from: data)
    guard case .unknown(let operation, let payload) = notification else {
      Issue.record("Expected unknown operation")
      return
    }
    #expect(operation == "future-op")
    #expect(payload["future_key"] == .object(["value": .integer(7)]))
  }

  @Test("Protocol lock matches specification pins")
  func protocolLockMatchesPins() throws {
    let data = try Data(
      contentsOf: repositoryRoot().appending(
        path: "MarimoNative/Resources/Sidecar/protocol-lock.json"))
    let lock = try JSONDecoder().decode(ProtocolLock.self, from: data)
    #expect(lock.marimoLSPCommit == "3998b939c4e3bb09853817344ba9a976eeac8a66")
    #expect(lock.marimoLSPVersion == "0.1.0")
    #expect(lock.marimoBaseVersion == "0.24.0")
    #expect(lock.kernelMarimoVersion == "0.24.0")
    #expect(lock.ownedDocumentVersion == "1")
    #expect(lock.commandMethod == "marimo/command")
    #expect(lock.notificationMethod == "marimo/kernelNotification")
    #expect(lock.schemaHash == "e58dbe06acbe252a5e37fecf4b65c71a24543f87f5923bc547da608ca97f7005")
  }

  private func fixture(_ name: String) -> URL {
    repositoryRoot().appending(path: "Tests/Fixtures/\(name)")
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private var allowedKeys: [String: Set<String>] {
    [
      "execute": ["kind", "notebookUri", "executable", "workingDirectory", "cells"],
      "update-ui-element": [
        "kind", "notebookUri", "kernelSessionId", "objectIds", "values", "request", "token",
      ],
      "interrupt": ["kind", "notebookUri", "kernelSessionId", "runId"],
      "delete-cell": ["kind", "notebookUri", "kernelSessionId", "cellId"],
      "send-stdin": ["kind", "notebookUri", "kernelSessionId", "text"],
      "close-session": ["kind", "notebookUri"],
      "restart-session": [
        "kind", "notebookUri", "executable", "workingDirectory", "createIfMissing",
      ],
      "move-session": ["kind", "notebookUri", "newNotebookUri"],
      "list-sessions": ["kind"], "shutdown-all-sessions": ["kind"],
      "print-notebook": ["kind", "document"], "parse-notebook": ["kind", "source"],
      "read-notebook-outputs": ["kind", "notebookUri", "sessionCachePath"],
      "set-display-theme": ["kind", "theme"],
      "export-html": ["kind", "notebookUri", "download", "files", "includeCode", "assetUrl"],
      "export-ipynb": ["kind", "notebookUri"], "export-markdown": ["kind", "notebookUri"],
    ]
  }

  private var requiredKeys: [String: Set<String>] {
    [
      "execute": ["kind", "notebookUri", "executable", "workingDirectory", "cells"],
      "update-ui-element": ["kind", "notebookUri", "kernelSessionId", "objectIds", "values"],
      "interrupt": ["kind", "notebookUri"],
      "delete-cell": ["kind", "notebookUri", "kernelSessionId", "cellId"],
      "send-stdin": ["kind", "notebookUri", "kernelSessionId", "text"],
      "close-session": ["kind", "notebookUri"],
      "restart-session": ["kind", "notebookUri", "executable", "workingDirectory"],
      "move-session": ["kind", "notebookUri", "newNotebookUri"],
      "list-sessions": ["kind"], "shutdown-all-sessions": ["kind"],
      "print-notebook": ["kind", "document"], "parse-notebook": ["kind", "source"],
      "read-notebook-outputs": ["kind", "notebookUri"], "set-display-theme": ["kind", "theme"],
      "export-html": ["kind", "notebookUri", "download", "files", "includeCode"],
      "export-ipynb": ["kind", "notebookUri"], "export-markdown": ["kind", "notebookUri"],
    ]
  }
}
