import MarimoDomain

extension NotebookRootView {
  func presentAssistant(
    for cell: NotebookCellState,
    index: Int,
    prompt: String? = nil,
    selection: String? = nil
  ) {
    store.leaveEditor()
    assistantConversation.attach(cell, index: index, selection: selection)
    if let prompt { assistantConversation.draft = prompt }
    store.assistantPresented = true
  }
}
