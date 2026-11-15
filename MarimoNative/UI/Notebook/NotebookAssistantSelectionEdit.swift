import Foundation
import MarimoDomain

extension NotebookAssistantConversation {
  func attach(_ cell: NotebookCellState, index: Int, selection: String? = nil) {
    guard !generating else { return }
    attachments.removeAll { $0.id == cell.runtimeID }
    attachments.append(
      Attachment(
        id: cell.runtimeID,
        index: index,
        code: cell.code,
        isTextCell: cell.editor.markdown != nil,
        runtimeError: NotebookRuntimeErrorContext.runtimeErrorContext(for: cell),
        selection: selection
      ))
  }

  static func completeReplacement(_ proposed: String, for attachment: Attachment) -> String? {
    guard let selection = attachment.selection else { return proposed }
    var ranges: [Range<String.Index>] = []
    var searchStart = attachment.code.startIndex
    while searchStart < attachment.code.endIndex,
      let range = attachment.code.range(
        of: selection, range: searchStart..<attachment.code.endIndex)
    {
      ranges.append(range)
      guard ranges.count < 2 else { return nil }
      searchStart = range.upperBound
    }
    guard let range = ranges.first else { return nil }
    var code = attachment.code
    code.replaceSubrange(range, with: proposed)
    return code
  }
}
