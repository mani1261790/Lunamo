import MarimoDomain
import MarimoOutput
import Testing

@Suite("Native output")
struct OutputTests {
  @Test("Wire output decodes string, error array, and object data with explicit mimetype")
  func typedWireDecode() throws {
    let values: [JSONValue] = [
      .string("hello"),
      .array([.object(["type": .string("syntax"), "msg": .string("bad")])]),
      .object(["answer": .integer(42)]),
    ]
    for data in values {
      let output = try MarimoOutput.decodeWireValue(
        .object([
          "channel": .string("output"),
          "mimetype": .string("application/json"),
          "data": data,
          "timestamp": .number(123.5),
        ])
      )
      #expect(output.data == data)
      #expect(output.channel == .output)
      #expect(output.mimeType == "application/json")
      #expect(output.timestamp == 123.5)
    }
    #expect(throws: MarimoOutputDecodingError.unsupportedDataShape) {
      try MarimoOutput.decodeWireValue(
        .object([
          "channel": .string("output"),
          "mimetype": .string("application/json"),
          "data": .integer(1),
        ])
      )
    }
  }

  @Test("Payloads over the fixed 128 MiB boundary are rejected before typed decode")
  func payloadLimit() {
    #expect(MarimoOutput.payloadByteLimit == 128 * 1_024 * 1_024)
    let wire: JSONValue = .object([
      "channel": .string("output"),
      "mimetype": .string("text/plain"),
      "data": .string(String(repeating: "x", count: 200)),
    ])
    #expect(throws: MarimoOutputDecodingError.payloadTooLarge(limit: 128)) {
      try MarimoOutput.decodeWireValue(wire, payloadByteLimit: 128)
    }
  }

  @Test("Registry selects every Gate D native renderer and safely falls back")
  func rendererRegistry() {
    let registry = OutputRendererRegistry()
    #expect(registry.renderer(for: "text/plain") == .text)
    #expect(registry.renderer(for: "application/json") == .json)
    #expect(registry.renderer(for: "application/vnd.marimo+error") == .error)
    #expect(registry.renderer(for: "application/vnd.marimo+traceback") == .traceback)
    #expect(registry.renderer(for: "image/png") == .image)
    #expect(registry.renderer(for: "text/csv") == .csv)
    #expect(registry.renderer(for: "text/html") == .html)
    #expect(registry.renderer(for: MIMEBundleResolver.mimeType) == .mimeBundle)
    #expect(registry.renderer(for: "image/svg+xml") == .webFallback)
    #expect(registry.renderer(for: "application/x-unknown") == .unsupported)
  }

  @Test("Text, JSON, error, traceback, PNG, and CSV prepare as native values")
  func nativePreparation() {
    assertText(prepared("text/plain", .string("hello")))
    assertJSON(prepared("application/json", .object(["answer": .integer(42)])))
    assertError(
      prepared(
        "application/vnd.marimo+error",
        .array([.object(["type": .string("syntax"), "msg": .string("bad")])])
      )
    )
    assertTraceback(
      prepared(
        "application/vnd.marimo+traceback",
        .string("Traceback\n  File \"/tmp/test.py\", line 7\nValueError")
      )
    )
    assertImage(
      prepared(
        "image/png",
        .string(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
      )
    )
    assertCSV(prepared("text/csv", .string("name,value\n\"a,b\",2\n")))
  }

  @Test("Unsupported and failed renderers preserve recoverable raw data")
  func rendererRecovery() {
    switch prepared("application/x-custom", .string("raw")) {
    case .unsupported(let mime, _, let raw):
      #expect(mime == "application/x-custom")
      #expect(raw == "raw")
    default: Issue.record("Expected unsupported output")
    }
    switch prepared("image/png", .string("not-an-image")) {
    case .failure(let mime, _, _, let raw):
      #expect(mime == "image/png")
      #expect(raw == "not-an-image")
    default: Issue.record("Expected renderer failure")
    }
  }

  @Test("Console preserves order and truncates oldest entries by bytes or lines")
  func boundedConsole() {
    #expect(ConsoleOutputBuffer.byteLimit == 10 * 1_024 * 1_024)
    #expect(ConsoleOutputBuffer.lineLimit == 100_000)
    var buffer = ConsoleOutputBuffer(maximumBytes: 10, maximumLines: 3)
    buffer.append(contentsOf: [textOutput("1\n2", channel: .stdout)])
    buffer.append(contentsOf: [textOutput("3\n4", channel: .stderr)])
    #expect(buffer.outputs.count == 2)
    #expect(buffer.outputs.first?.data == .string(ConsoleOutputBuffer.truncationNotice))
    #expect(buffer.outputs.last?.channel == .stderr)
    #expect(buffer.outputs.last?.data == .string("3\n4"))
  }

  @Test("Asset cache evicts the least recently used value")
  func assetCacheIsLRU() async {
    let cache = OutputAssetCache(costLimit: 8)
    await cache.insert(.text("a", masked: false), for: "a", cost: 4)
    await cache.insert(.text("b", masked: false), for: "b", cost: 4)
    _ = await cache.value(for: "a")
    await cache.insert(.text("c", masked: false), for: "c", cost: 4)
    #expect(await cache.value(for: "a") != nil)
    #expect(await cache.value(for: "b") == nil)
    #expect(await cache.value(for: "c") != nil)
  }

  private func prepared(_ mime: String, _ data: JSONValue) -> PreparedOutput {
    OutputPreparationService.prepareSynchronously(
      MarimoOutput(channel: .output, mimeType: mime, data: data)
    )
  }

  private func assertText(_ output: PreparedOutput) {
    guard case .text("hello", false) = output else {
      Issue.record("Expected native text")
      return
    }
  }

  private func assertJSON(_ output: PreparedOutput) {
    guard case .json(let root) = output else {
      Issue.record("Expected JSON tree")
      return
    }
    #expect(root.children.first?.label == "answer")
  }

  private func assertError(_ output: PreparedOutput) {
    guard case .errors(let errors) = output else {
      Issue.record("Expected errors")
      return
    }
    #expect(errors.first?.kind == "syntax")
    #expect(errors.first?.message == "bad")
  }

  private func assertTraceback(_ output: PreparedOutput) {
    guard case .traceback(let lines) = output else {
      Issue.record("Expected traceback")
      return
    }
    #expect(lines[1].fileURL?.path == "/tmp/test.py")
    #expect(lines[1].line == 7)
  }

  private func assertImage(_ output: PreparedOutput) {
    guard case .image(let image) = output else {
      Issue.record("Expected image")
      return
    }
    #expect(image.pixelWidth == 1)
    #expect(image.pixelHeight == 1)
  }

  private func assertCSV(_ output: PreparedOutput) {
    guard case .csv(let table) = output else {
      Issue.record("Expected CSV")
      return
    }
    #expect(table.columns == ["name", "value"])
    #expect(table.rows == [["a,b", "2"]])
  }
}
