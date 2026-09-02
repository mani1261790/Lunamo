import MarimoApplication
import MarimoBackend
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
  }
}
