import MarimoApplication
import SwiftUI

struct NotebookLogReviewView: View {
  @ObservedObject var store: NotebookStore

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(store.reviewableLogText)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding()
      }
      .accessibilityLabel("Reviewed diagnostic log")
      .navigationTitle("Review Logs Before Export")
      .toolbar {
        Button("Export Reviewed Logs…") { NotebookLogExportActions.saveReviewedLog(store) }
        Button("Done") { store.backendLogsPresented = false }
      }
    }
    .frame(minWidth: 640, minHeight: 420)
  }
}
