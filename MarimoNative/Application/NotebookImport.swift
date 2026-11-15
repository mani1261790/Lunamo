import Foundation
import MarimoBackend

public struct NotebookImportDraft: Sendable, Equatable {
  public let sourceURL: URL
  public let convertedSource: String
  public let suggestedFilename: String
  public let requiredPackages: [String]

  public init(
    sourceURL: URL,
    convertedSource: String,
    suggestedFilename: String,
    requiredPackages: [String] = []
  ) {
    self.sourceURL = sourceURL
    self.convertedSource = convertedSource
    self.suggestedFilename = suggestedFilename
    self.requiredPackages = requiredPackages
  }
}

public enum NotebookImportError: LocalizedError, Sendable, Equatable {
  case unsupportedFormat(String)
  case invalidConvertedNotebook
  case sourceAndDestinationMatch
  case destinationMustBePython
  case convertedNotebookCouldNotOpen

  public var errorDescription: String? {
    switch self {
    case .unsupportedFormat(let extensionName):
      "Unsupported import format: .\(extensionName)"
    case .invalidConvertedNotebook:
      "marimo produced an invalid notebook during conversion."
    case .sourceAndDestinationMatch:
      "The converted notebook must be saved separately from the source file."
    case .destinationMustBePython:
      "The converted notebook must be saved as a .py file."
    case .convertedNotebookCouldNotOpen:
      "The converted notebook was saved but could not be opened."
    }
  }
}

extension NotebookStore {
  public func prepareImport(from sourceURL: URL) async throws -> NotebookImportDraft {
    let sourceURL = sourceURL.standardizedFileURL
    let format: NotebookImportSourceFormat
    let suggestedFilename: String
    switch sourceURL.pathExtension.lowercased() {
    case "ipynb":
      format = .ipynb
      suggestedFilename = sourceURL.deletingPathExtension().lastPathComponent + ".py"
    case "py":
      format = .python
      suggestedFilename = sourceURL.deletingPathExtension().lastPathComponent + "_marimo.py"
    case let extensionName:
      throw NotebookImportError.unsupportedFormat(extensionName)
    }

    openState = .loading(sourceURL)
    userFacingError = nil
    do {
      let snapshot = try await documentService.readSnapshot(at: sourceURL)
      if backendStatus != .ready {
        try await backend.start()
        backendStatus = await backend.status()
      }
      let convertedSource = try await backend.convertNotebook(
        source: snapshot.source,
        format: format
      )
      guard case .success = try await backend.parseNotebook(source: convertedSource) else {
        throw NotebookImportError.invalidConvertedNotebook
      }
      openState = .idle
      return NotebookImportDraft(
        sourceURL: sourceURL,
        convertedSource: convertedSource,
        suggestedFilename: suggestedFilename,
        requiredPackages: format == .ipynb ? pep723Dependencies(in: convertedSource) : []
      )
    } catch {
      openState = .failed(sourceURL, error.localizedDescription)
      presentError(
        code: .documentConvert,
        cause: error.localizedDescription,
        target: sourceURL.path,
        recoveryActions: ["Try Again", "Open Another Notebook"]
      )
      throw error
    }
  }

  public func saveImportedNotebook(_ draft: NotebookImportDraft, to destinationURL: URL)
    async throws
  {
    let sourceURL = draft.sourceURL.standardizedFileURL
    let destinationURL = destinationURL.standardizedFileURL
    guard sourceURL != destinationURL else {
      throw NotebookImportError.sourceAndDestinationMatch
    }
    guard destinationURL.pathExtension.lowercased() == "py" else {
      throw NotebookImportError.destinationMustBePython
    }

    _ = try await fileWriter.write(
      source: draft.convertedSource,
      to: destinationURL,
      expecting: .unchecked
    )
    await open(destinationURL)
    guard openState == .loaded(destinationURL) else {
      throw NotebookImportError.convertedNotebookCouldNotOpen
    }
    missingPackages = draft.requiredPackages
  }

  public func reportImportSaveFailure(_ error: any Error, sourceURL: URL) {
    presentError(
      code: .documentSave,
      cause: error.localizedDescription,
      target: sourceURL.path,
      recoveryActions: ["Choose Another Location", "Try Again"]
    )
  }
}

private func pep723Dependencies(in source: String) -> [String] {
  guard let declaration = source.range(of: "# dependencies = [") else { return [] }
  let suffix = source[declaration.upperBound...]
  guard let closing = suffix.range(of: "]") else { return [] }
  let contents = String(suffix[..<closing.lowerBound])
  guard let expression = try? NSRegularExpression(pattern: #"[\"']([^\"']+)[\"']"#) else {
    return []
  }
  let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
  var seen: Set<String> = []
  return expression.matches(in: contents, range: range).compactMap { match in
    guard let valueRange = Range(match.range(at: 1), in: contents) else { return nil }
    let value = String(contents[valueRange])
    return seen.insert(value).inserted ? value : nil
  }
}
