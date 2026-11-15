import Foundation
import MarimoDomain
import Testing

@testable import MarimoUI

@Suite("Assistant conversation")
@MainActor
struct NotebookAssistantTests {
  @Test("Exactly one complete Python fence becomes a cell replacement")
  func codeSuggestionParser() {
    let response = """
      Use this complete replacement:

      ```python
      value = 42
      print(value)
      ```
      """
    #expect(
      AssistantCodeSuggestionParser.replacement(from: response)
        == "value = 42\nprint(value)"
    )
    #expect(AssistantCodeSuggestionParser.replacement(from: "Use `value = 42`.") == nil)
    #expect(
      AssistantCodeSuggestionParser.replacement(
        from: "```python\na = 1\n```\n```python\nb = 2\n```") == nil
    )
    #expect(AssistantCodeSuggestionParser.replacement(from: "```swift\nlet x = 1\n```") == nil)
  }

  @Test("Attachments snapshot code and deduplicate by cell identity")
  func attachments() {
    let conversation = NotebookAssistantConversation()
    var cell = NotebookDocumentState().cells[0]
    cell.code = "value = 1"
    conversation.attach(cell, index: 1)
    cell.code = "value = 2"
    #expect(conversation.attachments[0].code == "value = 1")
    conversation.attach(cell, index: 3)
    #expect(conversation.attachments.count == 1)
    #expect(conversation.attachments[0].code == "value = 2")
    #expect(conversation.attachments[0].index == 3)
  }

  @Test("A unique selected range is replaced without exposing the rest as model context")
  func selectedRangeReplacement() throws {
    let conversation = NotebookAssistantConversation()
    var cell = NotebookDocumentState().cells[0]
    cell.code = "value = 1\nprint(value)"
    conversation.attach(cell, index: 1, selection: "value = 1")
    let attachment = try #require(conversation.attachments.first)

    #expect(attachment.selection == "value = 1")
    #expect(
      NotebookAssistantConversation.completeReplacement("value = 42", for: attachment)
        == "value = 42\nprint(value)"
    )
  }

  @Test("An ambiguous selected range is never applied automatically")
  func ambiguousSelectedRange() throws {
    let conversation = NotebookAssistantConversation()
    var cell = NotebookDocumentState().cells[0]
    cell.code = "value = 1\nvalue = 1"
    conversation.attach(cell, index: 1, selection: "value = 1")
    let attachment = try #require(conversation.attachments.first)

    #expect(NotebookAssistantConversation.completeReplacement("value = 2", for: attachment) == nil)
  }

  @Test("Error attachments include the latest runtime failure")
  func errorAttachmentContext() {
    let conversation = NotebookAssistantConversation()
    var cell = NotebookDocumentState().cells[0]
    cell.code = "raise ValueError('bad')"
    cell.runtime.status = .idle
    cell.runtime.output = MarimoOutput(
      channel: .marimoError,
      mimeType: "application/vnd.marimo+error",
      data: .array([])
    )
    cell.runtime.console = [
      MarimoOutput(channel: .stderr, mimeType: "text/plain", data: .string("ValueError: bad"))
    ]

    conversation.attach(cell, index: 2)

    #expect(conversation.attachments[0].runtimeError == "ValueError: bad")
  }

  @Test("New conversation clears draft and cell references without changing the document")
  func reset() {
    let conversation = NotebookAssistantConversation()
    let document = NotebookDocumentState()
    conversation.attach(document.cells[0], index: 1)
    conversation.draft = "Explain this cell"
    conversation.reset()
    #expect(conversation.attachments.isEmpty)
    #expect(conversation.fileAttachments.isEmpty)
    #expect(conversation.draft.isEmpty)
    #expect(conversation.messages.isEmpty)
    #expect(!conversation.generating)
    #expect(!document.dirty)
  }

  @Test("New conversation archives current context and restores it without touching the document")
  func conversationHistory() throws {
    let conversation = NotebookAssistantConversation()
    var document = NotebookDocumentState()
    document.cells[0].code = "answer = 42"
    conversation.attach(document.cells[0], index: 1)
    conversation.draft = "Explain this"

    conversation.startNewConversation()

    #expect(conversation.history.count == 1)
    #expect(conversation.history[0].title == "answer = 42")
    #expect(conversation.history[0].contextCount == 1)
    #expect(conversation.attachments.isEmpty)
    #expect(conversation.draft.isEmpty)

    let archived = try #require(conversation.history.first)
    conversation.restore(archived)

    #expect(conversation.history.isEmpty)
    #expect(conversation.attachments.count == 1)
    #expect(conversation.attachments[0].code == "answer = 42")
    #expect(conversation.draft == "Explain this")
    #expect(!document.dirty)
  }

  @Test("Document reset clears both the active conversation and its session history")
  func documentResetClearsHistory() {
    let conversation = NotebookAssistantConversation()
    let document = NotebookDocumentState()
    conversation.attach(document.cells[0], index: 1)
    conversation.startNewConversation()
    #expect(!conversation.history.isEmpty)

    conversation.reset()

    #expect(conversation.history.isEmpty)
    #expect(conversation.attachments.isEmpty)
    #expect(conversation.messages.isEmpty)
  }

  @Test("Conversation history remains bounded to the latest twenty conversations")
  func boundedConversationHistory() {
    let conversation = NotebookAssistantConversation()
    for index in 0...20 {
      conversation.draft = "Conversation \(index)"
      conversation.startNewConversation()
    }

    #expect(conversation.history.count == 20)
    #expect(conversation.history.first?.title == "Conversation 20")
    #expect(conversation.history.last?.title == "Conversation 1")
  }

  @Test("File attachments snapshot text content and deduplicate by source")
  func fileAttachments() throws {
    let conversation = NotebookAssistantConversation()
    let url = FileManager.default.temporaryDirectory
      .appending(path: "assistant-\(UUID().uuidString).txt")
    try Data("first".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    conversation.attachFiles([url])
    #expect(conversation.fileAttachments.count == 1)
    #expect(conversation.fileAttachments[0].name == url.lastPathComponent)
    #expect(conversation.fileAttachments[0].kind == .text)
    #expect(String(decoding: conversation.fileAttachments[0].data, as: UTF8.self) == "first")

    try Data("second".utf8).write(to: url)
    conversation.attachFiles([url])
    #expect(conversation.fileAttachments.count == 1)
    #expect(String(decoding: conversation.fileAttachments[0].data, as: UTF8.self) == "second")
  }
}
