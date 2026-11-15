import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import Testing

@Suite("NotebookStore")
@MainActor
struct NotebookStoreTests {
  @Test("Intents own mutable document state")
  func intentsMutateState() async {
    let store = NotebookStore(backend: PlaceholderMarimoBackend())
    let initialCell = store.document.cells[0]

    await store.send(.updateCode(cellID: initialCell.runtimeID, code: "value = 1"))
    #expect(store.document.cells[0].code == "value = 1")
    #expect(store.document.dirty)
    #expect(store.document.sourceRevision == 1)

    await store.send(.addCell)
    #expect(store.document.cells.count == 2)
    #expect(store.document.selectedCellID == store.document.cells[1].runtimeID)

    let previousFirstID = store.document.cells[0].runtimeID
    await store.send(.insertCellAt(0))
    #expect(store.document.cells.count == 3)
    #expect(store.document.cells[1].runtimeID == previousFirstID)
    #expect(store.document.selectedCellID == store.document.cells[0].runtimeID)
  }

  @Test("Checked code edits apply once and reject stale, missing, or text cells")
  func checkedCodeEdits() async {
    var document = NotebookDocumentState()
    let codeCellID = document.cells[0].runtimeID
    let store = NotebookStore(backend: PlaceholderMarimoBackend(), document: document)

    #expect(
      store.checkedCodeEditState(
        cellID: codeCellID, expectedCode: "", replacementCode: "value = 42") == .ready)
    #expect(
      await store.applyCheckedCodeEdit(
        cellID: codeCellID, expectedCode: "", replacementCode: "value = 42")
        == .alreadyApplied)
    #expect(store.document.cells[0].code == "value = 42")
    #expect(store.document.dirty)
    #expect(
      store.checkedCodeEditState(
        cellID: codeCellID, expectedCode: "", replacementCode: "value = 43")
        == .sourceChanged)
    #expect(
      store.checkedCodeEditState(
        cellID: UUID(), expectedCode: "", replacementCode: "value = 43") == .missingCell)

    document.cells[0].editor.markdown = "# Heading"
    let textStore = NotebookStore(backend: PlaceholderMarimoBackend(), document: document)
    #expect(
      textStore.checkedCodeEditState(
        cellID: codeCellID, expectedCode: "", replacementCode: "value = 43") == .textCell)
  }
}
