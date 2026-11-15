import MarimoDomain
import Testing

@Suite("Cell drag destinations")
struct CellReorderPositionTests {
  @Test("Dragging up, down, to the first gap and to the last gap")
  func destinations() {
    #expect(CellReorderPosition.destination(source: 0, insertionBoundary: 4, count: 4) == 3)
    #expect(CellReorderPosition.destination(source: 3, insertionBoundary: 0, count: 4) == 0)
    #expect(CellReorderPosition.destination(source: 1, insertionBoundary: 3, count: 4) == 2)
    #expect(CellReorderPosition.destination(source: 2, insertionBoundary: 1, count: 4) == 1)
  }

  @Test("Dropping beside itself or outside the notebook does not move a cell")
  func unchanged() {
    #expect(CellReorderPosition.destination(source: 1, insertionBoundary: 1, count: 3) == nil)
    #expect(CellReorderPosition.destination(source: 1, insertionBoundary: 2, count: 3) == nil)
    #expect(CellReorderPosition.destination(source: 0, insertionBoundary: 1, count: 1) == nil)
    #expect(CellReorderPosition.destination(source: 0, insertionBoundary: 0, count: 0) == nil)
    #expect(CellReorderPosition.destination(source: 1, insertionBoundary: 4, count: 3) == nil)
  }
}
