import AppKit
import MarimoApplication
import SwiftUI

public struct NotebookMenuCommands: Commands {
  @ObservedObject private var store: NotebookStore

  public init(store: NotebookStore) {
    self.store = store
  }

  public var body: some Commands {
    SidebarCommands()

    CommandGroup(replacing: .newItem) {
      Button("Open Notebook…") {
        NotebookOpenActions.open(store)
      }
      .keyboardShortcut("o", modifiers: [.command])
    }

    CommandMenu("Notebook") {
      Button("Run Cell and Advance") {
        guard let cellID = store.document.selectedCellID else { return }
        Task { await store.requestRunCell(cellID, advance: true) }
      }
      .keyboardShortcut(.return, modifiers: [.shift])
      .disabled(!canRunSelectedCell)
      Button("Run Cell") {
        guard let cellID = store.document.selectedCellID else { return }
        Task { await store.requestRunCell(cellID) }
      }
      .keyboardShortcut(.return, modifiers: [.command])
      .disabled(!canRunSelectedCell)
      Button("Run Cell and Insert Below") {
        guard let cellID = store.document.selectedCellID else { return }
        Task { await store.requestRunCell(cellID, insertBelow: true) }
      }
      .keyboardShortcut(.return, modifiers: [.option])
      .disabled(!canRunSelectedCell)
      Button("Run All") {
        Task { await store.requestRunAll() }
      }
      .keyboardShortcut(.return, modifiers: [.command, .shift])
      .disabled(!canRun)
      Button("Interrupt") {
        Task { await store.requestInterrupt() }
      }
      .keyboardShortcut(".", modifiers: [.command])
      .disabled(!store.sessionAllowsInterrupt)
      Button(store.forceRestartAvailable ? "Force Restart Kernel" : "Restart Kernel") {
        Task { await store.requestRestartKernel() }
      }
      .disabled(!store.sessionAllowsRestart)

      Divider()

      Button("Focus Selected Cell Editor") {
        if let cellID = store.document.selectedCellID {
          store.focusEditor(cellID)
        }
      }
      .keyboardShortcut(.return, modifiers: [])
      .disabled(store.document.selectedCellID == nil || store.focusedCellID != nil)
      Button("Leave Cell Editor") {
        store.leaveEditor()
      }
      .keyboardShortcut(.escape, modifiers: [])
      .disabled(store.focusedCellID == nil)

      Divider()

      Button("Move Cell Up") {
        moveSelectedCell(by: -1)
      }
      .keyboardShortcut(.upArrow, modifiers: [.command, .option])
      .disabled(!canMoveSelectedCell(by: -1))
      Button("Move Cell Down") {
        moveSelectedCell(by: 1)
      }
      .keyboardShortcut(.downArrow, modifiers: [.command, .option])
      .disabled(!canMoveSelectedCell(by: 1))
      Button("Delete Selected Cell") {
        guard let cellID = store.document.selectedCellID else { return }
        Task { await store.send(.deleteCell(cellID)) }
      }
      .keyboardShortcut(.delete, modifiers: [.command, .shift])
      .disabled(store.document.selectedCellID == nil || store.focusedCellID != nil)

      Divider()

      Button("Toggle Inspector") {
        store.inspectorPresented.toggle()
      }
      .keyboardShortcut("i", modifiers: [.command, .option])
    }

    CommandGroup(after: .saveItem) {
      Button("Save Notebook") {
        NotebookSaveActions.save(store)
      }
      .keyboardShortcut("s", modifiers: [.command])
      .disabled(store.saveConflictURL != nil)
      Button("Save Notebook As…") {
        NotebookSaveActions.saveAs(store)
      }
      .keyboardShortcut("s", modifiers: [.command, .shift])
    }
  }

  private func canMoveSelectedCell(by offset: Int) -> Bool {
    guard let selected = store.document.selectedCellID,
      let index = store.document.cells.firstIndex(where: { $0.runtimeID == selected })
    else { return false }
    return store.document.cells.indices.contains(index + offset)
  }

  private var canRun: Bool {
    store.backendStatus == .ready && store.environmentAllowsExecutionRequest
      && store.sessionAllowsRun && store.documentAllowsExecution
  }

  private var canRunSelectedCell: Bool {
    canRun && store.document.selectedCellID != nil
  }

  private func moveSelectedCell(by offset: Int) {
    guard let selected = store.document.selectedCellID,
      let index = store.document.cells.firstIndex(where: { $0.runtimeID == selected })
    else { return }
    Task { await store.send(.moveCell(selected, to: index + offset)) }
  }
}
