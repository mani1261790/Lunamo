import MarimoApplication
import SwiftUI

struct NotebookLogReviewView: View {
  @ObservedObject var store: NotebookStore
  @State private var includeDetails = false
  @State private var reviewedText = ""

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        Text(
          localizedUI(
            "Nothing is sent automatically. Save this report locally and share it only if you choose."
          )
        )
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        Toggle(localizedUI("Include detailed logs"), isOn: $includeDetails)
          .onChange(of: includeDetails) { _, included in
            reviewedText =
              included
              ? store.diagnosticSummary + "\n\n" + store.reviewableLogText
              : store.diagnosticSummary
          }
        if includeDetails {
          Text(
            localizedUI(
              "Detailed logs may contain file names, code or private data. Remove anything you do not want to share below."
            )
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
        TextEditor(text: $reviewedText)
          .font(.system(.body, design: .monospaced))
          .accessibilityLabel(localizedUI("Reviewed diagnostic log"))
      }
      .padding()
      .navigationTitle(localizedUI("Review Logs Before Export"))
      .toolbar {
        Button(localizedUI("Export Reviewed Logs…")) {
          NotebookLogExportActions.saveReviewedLog(store, text: reviewedText)
        }
        .disabled(reviewedText.isEmpty)
        Button(localizedUI("Done")) { store.backendLogsPresented = false }
      }
    }
    .frame(minWidth: 640, minHeight: 420)
    .onAppear { reviewedText = store.diagnosticSummary }
  }
}
