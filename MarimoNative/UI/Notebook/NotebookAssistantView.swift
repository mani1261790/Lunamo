import Foundation
import FoundationModels
import MarimoApplication
import MarimoDomain
import SwiftUI

struct NotebookAssistantView: View {
  enum Action: String, CaseIterable, Identifiable {
    case explain = "Explain"
    case suggestFix = "Suggest Fix"

    var id: Self { self }
  }

  @ObservedObject var store: NotebookStore
  @Environment(\.dismiss) private var dismiss
  @State private var action: Action = .explain
  @State private var response = ""
  @State private var errorMessage: String?
  @State private var generating = false

  private let model = SystemLanguageModel.default

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Label("Notebook Assistant", systemImage: "apple.intelligence")
          .font(.title2.weight(.semibold))
        Spacer()
        Button("Done") { dismiss() }
      }

      availabilityBanner

      Picker("Action", selection: $action) {
        ForEach(Action.allCases) { item in
          Text(LocalizedStringKey(item.rawValue)).tag(item)
        }
      }
      .pickerStyle(.segmented)

      GroupBox("Selected Cell") {
        ScrollView {
          Text(selectedCell?.code ?? "Select a cell first.")
            .font(.body.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(minHeight: 110, maxHeight: 180)
      }

      HStack {
        Button {
          Task { await generate() }
        } label: {
          if generating {
            ProgressView()
              .controlSize(.small)
          } else {
            Label("Generate Preview", systemImage: "sparkles")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canGenerate)

        Text("Runs on device. Nothing is sent to an external service.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }

      GroupBox("Preview") {
        ScrollView {
          Text(response.isEmpty ? "The generated result will appear here." : response)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(minHeight: 150)
      }

      HStack {
        Spacer()
        Button("Replace Selected Cell") { applyPreview() }
          .disabled(action != .suggestFix || response.isEmpty || selectedCell == nil)
          .help("Only changes the editor. It does not save or run the notebook.")
      }
    }
    .padding(20)
    .frame(width: 680, height: 620)
  }

  @ViewBuilder
  private var availabilityBanner: some View {
    switch model.availability {
    case .available:
      if model.supportsLocale(Locale(identifier: "ja")) {
        Label(
          "Apple Intelligence is available, including Japanese.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
      } else {
        Label(
          "Apple Intelligence is available, but Japanese is not supported by this model.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
      }
    case .unavailable(let reason):
      Label(unavailableMessage(reason), systemImage: "xmark.circle.fill")
        .foregroundStyle(.secondary)
    }
  }

  private var selectedCell: NotebookCellState? {
    guard let id = store.document.selectedCellID else { return nil }
    return store.document.cells.first { $0.runtimeID == id }
  }

  private var canGenerate: Bool {
    !generating && selectedCell != nil && model.availability == .available
      && model.supportsLocale(Locale(identifier: "ja"))
  }

  @MainActor
  private func generate() async {
    guard let source = selectedCell?.code else { return }
    guard source.utf8.count <= 24_000 else {
      errorMessage = "The selected cell is too large. Shorten it and try again."
      return
    }
    generating = true
    response = ""
    errorMessage = nil
    defer { generating = false }

    let instruction: String
    switch action {
    case .explain:
      instruction = "Explain this Python cell in clear Japanese. Do not propose execution."
    case .suggestFix:
      instruction = "Return only a corrected Python cell, without Markdown fences or commentary."
    }
    let session = LanguageModelSession(
      model: model,
      instructions: "You are an on-device notebook assistant. Never claim code was executed."
    )
    do {
      let result = try await session.respond(to: "\(instruction)\n\nPython cell:\n\(source)")
      response = result.content
    } catch let error as LanguageModelSession.GenerationError {
      errorMessage = generationMessage(error)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func applyPreview() {
    guard action == .suggestFix, !response.isEmpty, let cell = selectedCell else { return }
    store.focusEditor(cell.runtimeID)
    Task { await store.send(.updateCode(cellID: cell.runtimeID, code: response)) }
  }

  private func unavailableMessage(
    _ reason: SystemLanguageModel.Availability.UnavailableReason
  ) -> LocalizedStringKey {
    switch reason {
    case .deviceNotEligible: "This Mac does not support Apple Intelligence."
    case .appleIntelligenceNotEnabled:
      "Turn on Apple Intelligence in System Settings to use the assistant."
    case .modelNotReady: "The on-device model is still being prepared. Try again later."
    @unknown default: "Apple Intelligence is currently unavailable."
    }
  }

  private func generationMessage(_ error: LanguageModelSession.GenerationError) -> String {
    switch error {
    case .exceededContextWindowSize:
      String(localized: "The cell is too large for the on-device model. Shorten it and try again.")
    case .guardrailViolation:
      String(
        localized:
          "The request was stopped by Apple Intelligence safety checks. Edit the cell or request and try again."
      )
    case .unsupportedLanguageOrLocale:
      String(localized: "The current language is not supported by the on-device model.")
    case .assetsUnavailable:
      String(localized: "The on-device model is not ready. Try again after its download finishes.")
    case .rateLimited, .concurrentRequests:
      String(localized: "The model is busy. Wait a moment and try again.")
    case .refusal:
      String(localized: "Apple Intelligence declined this request. Revise it and try again.")
    case .unsupportedGuide, .decodingFailure:
      String(localized: "The model could not create a usable response. Try again.")
    @unknown default:
      error.localizedDescription
    }
  }
}
