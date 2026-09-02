import Foundation
import MarimoApplication
import Testing

@Suite("Document source loading")
struct DocumentServiceTests {
  @Test("UTF-8 BOM is accepted and removed")
  func removesBOM() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    var data = Data([0xEF, 0xBB, 0xBF])
    data.append(Data("print('ok')\n".utf8))
    try data.write(to: url)
    let service = DocumentService()
    #expect(try await service.readSource(at: url) == "print('ok')\n")
    let snapshot = try await service.readSnapshot(at: url)
    #expect(snapshot.identity == (try await AtomicFileWriter().identity(at: url)))
  }

  @Test("Invalid UTF-8 is rejected without replacement")
  func rejectsInvalidUTF8() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data([0xFF, 0xFE]).write(to: url)
    await #expect(throws: DocumentOpenError.invalidUTF8) {
      try await DocumentService().readSource(at: url)
    }
  }

  @Test("Sources larger than 20 MiB are rejected before reading")
  func rejectsOversizedSource() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(DocumentService.maximumSourceBytes + 1))
    try handle.close()
    await #expect(throws: DocumentOpenError.self) {
      try await DocumentService().readSource(at: url)
    }
  }

  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "marimonative-document-\(UUID().uuidString).py")
  }
}
