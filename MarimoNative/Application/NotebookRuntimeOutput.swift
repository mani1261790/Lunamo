import Foundation
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import MarimoWidgets
import OSLog

extension NotebookStore {
  func applyCellOperation(
    _ payload: [String: JSONValue],
    executedSource: String?,
    replacingConsole: Bool = false
  ) {
    guard let cellID = payload.string(for: "cell_id"),
      let index = document.cells.firstIndex(where: { $0.runtimeID.uuidString == cellID })
    else {
      MarimoLog.kernel.debug("Ignoring cell-op for an unknown cell")
      return
    }
    var runtime = document.cells[index].runtime
    if payload.keys.contains("output") {
      if let value = payload["output"], value != .null {
        runtime.output = decodeOutput(value, defaultChannel: .output)
        runtime.stale = false
      } else {
        runtime.output = nil
      }
      let descriptors = sliderDescriptors(from: runtime.output)
      widgetValueStore.synchronize(cellID: cellID, descriptors: descriptors)
      runtime.widgetIDs = descriptors.map(\.objectID)
    }
    if let console = payload["console"] {
      if let prompt = stdinPrompt(from: console) { runtime.stdinPrompt = prompt }
      switch console {
      case .array(let values):
        if values.isEmpty || replacingConsole {
          runtime.console.removeAll()
        }
        if !values.isEmpty {
          appendConsole(values, to: &runtime)
        }
      case .null:
        break
      default:
        appendConsole([console], to: &runtime)
      }
    }
    if let status = payload.string(for: "status"),
      let accepted = ExecutionStatus(rawValue: status)
    {
      runtime.status = accepted
      if accepted == .queued || accepted == .running { sessionState = .running }
    }
    if let stale = payload.bool(for: "stale_inputs") { runtime.stale = stale }
    if let executedSource { runtime.lastExecutedCode = executedSource }
    document.cells[index].runtime = runtime
  }

  private func appendConsole(_ values: [JSONValue], to runtime: inout CellRuntimeState) {
    let decoded = values.map { decodeOutput($0, defaultChannel: .stdout) }
    var buffer = ConsoleOutputBuffer(outputs: runtime.console)
    buffer.append(contentsOf: decoded)
    runtime.console = buffer.outputs
  }

  private func decodeOutput(
    _ value: JSONValue,
    defaultChannel: OutputChannel
  ) -> MarimoOutput {
    if case .string = value {
      return MarimoOutput(channel: defaultChannel, mimeType: "text/plain", data: value)
    }
    do {
      return try MarimoOutput.decodeWireValue(value)
    } catch MarimoOutputDecodingError.payloadTooLarge(let limit) {
      MarimoLog.output.error("Rejected output larger than \(limit, privacy: .public) bytes")
      return MarimoOutput(
        channel: defaultChannel,
        mimeType: "application/vnd.marimonative+renderer-error",
        data: .object([
          "message": .string("Output payload exceeds the \(limit)-byte limit."),
          "size": .integer(Int64(value.estimatedUTF8ByteCount(upTo: Int.max))),
        ])
      )
    } catch {
      MarimoLog.output.error("Could not decode an output payload")
      return MarimoOutput.displayFailure(error, rawValue: value, channel: defaultChannel)
    }
  }

  private func stdinPrompt(from value: JSONValue) -> StdinPromptState? {
    let values: [JSONValue]
    if case .array(let array) = value { values = array } else { values = [value] }
    for value in values.reversed() {
      guard case .object(let object) = value,
        object.string(for: "channel") == "stdin"
      else { continue }
      return StdinPromptState(
        prompt: object.string(for: "data") ?? "",
        password: object.string(for: "mimetype") == "text/password"
      )
    }
    return nil
  }
}
