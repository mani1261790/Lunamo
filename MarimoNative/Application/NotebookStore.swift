import Combine
import Foundation
import MarimoBackend
import MarimoDomain

@MainActor
public final class NotebookStore: ObservableObject {
  public enum OpenState: Sendable, Equatable {
    case idle
    case loading(URL)
    case loaded(URL)
    case invalidSyntax(URL, line: Int?, column: Int?)
    case convertible(URL)
    case failed(URL, String)
  }

  @Published public private(set) var document: NotebookDocumentState
  @Published public private(set) var backendStatus: BackendStatus = .unavailable
  @Published public private(set) var openState: OpenState = .idle

  private let backend: any MarimoBackend
  private let documentService: DocumentService

  public init(
    backend: any MarimoBackend,
    document: NotebookDocumentState = NotebookDocumentState(),
    documentService: DocumentService = DocumentService()
  ) {
    self.backend = backend
    self.document = document
    self.documentService = documentService
  }

  public func send(_ intent: NotebookIntent) {
    switch intent {
    case .addCell:
      let cell = NotebookCellState()
      document.cells.append(cell)
      document.selectedCellID = cell.runtimeID
      document.sourceRevision += 1
      document.dirty = true
    case .selectCell(let cellID):
      guard document.cells.contains(where: { $0.runtimeID == cellID }) else { return }
      document.selectedCellID = cellID
    case .updateCode(let cellID, let code):
      guard let index = document.cells.firstIndex(where: { $0.runtimeID == cellID }) else { return }
      guard document.cells[index].code != code else { return }
      document.cells[index].code = code
      document.cells[index].editor.textDocumentVersion += 1
      document.sourceRevision += 1
      document.dirty = true
    }
  }

  public func refreshBackendStatus() async {
    backendStatus = await backend.status()
  }

  public func startBackend() async {
    do {
      try await backend.start()
      backendStatus = await backend.status()
    } catch {
      backendStatus = .unavailable
    }
  }

  public func open(_ url: URL) async {
    openState = .loading(url)
    do {
      let source = try await documentService.readSource(at: url)
      if backendStatus != .ready {
        try await backend.start()
        backendStatus = await backend.status()
      }
      switch try await backend.parseNotebook(source: source) {
      case .success(let parsed):
        let cells = parsed.cells.map { cell in
          NotebookCellState(
            sourceID: cell.sourceID,
            code: cell.code,
            name: cell.name,
            configuration: cell.configuration
          )
        }
        document = NotebookDocumentState(sourceURL: url, cells: cells, dirty: false)
        openState = .loaded(url)
      case .invalidSyntax(let line, let column):
        openState = .invalidSyntax(url, line: line, column: column)
      case .convertible:
        openState = .convertible(url)
      }
    } catch {
      openState = .failed(url, String(describing: error))
    }
  }

  public func shutdownBackend() async {
    await backend.shutdown()
    backendStatus = .unavailable
  }
}
