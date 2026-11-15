import Foundation
import FoundationModels
import ImageIO
import MarimoApplication
import MarimoDomain
import SwiftUI
import UniformTypeIdentifiers

struct NotebookAssistantView: View {
  @ObservedObject var store: NotebookStore
  @ObservedObject var conversation: NotebookAssistantConversation
  @FocusState var promptFocused: Bool
  @State var fileImporterPresented = false
  @State var historyPresented = false
  @State var expandedSuggestionIDs: Set<UUID> = []
  @Environment(\.accessibilityReduceTransparency) var reduceTransparency
  @Environment(\.colorSchemeContrast) var contrast

  var body: some View {
    GeometryReader { geometry in
      assistantContent(compact: geometry.size.width < 360)
    }
    .accessibilityIdentifier("notebook.assistant.sidebar")
    .fileImporter(
      isPresented: $fileImporterPresented,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        conversation.attachFiles(urls)
        promptFocused = true
      case .failure(let error):
        conversation.reportAttachmentFailure(error)
      }
    }
  }

  private func assistantContent(compact: Bool) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text(historyPresented ? localizedUI("Conversation History") : "Assistant")
            .font(.system(size: 15, weight: .semibold))
          Text(historyPresented ? localizedUI("This Notebook Session") : "Apple Intelligence")
            .font(.caption).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(minWidth: 0, alignment: .leading)
        Spacer()
        HStack(spacing: 4) {
          Button {
            conversation.startNewConversation()
            historyPresented = false
            promptFocused = true
          } label: {
            Image(systemName: "square.and.pencil")
          }
          .accessibilityLabel("New Conversation")
          .help("New Conversation")
          Button {
            historyPresented.toggle()
          } label: {
            Image(systemName: "clock.arrow.circlepath")
              .symbolVariant(historyPresented ? .fill : .none)
          }
          .accessibilityLabel("Conversation History")
          .help("Conversation History")
        }
        .fixedSize()
        Button {
          store.leaveEditor()
          store.assistantPresented = false
        } label: {
          Image(systemName: "sparkles")
            .font(.system(size: 16))
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .accessibilityLabel("Notebook Assistant")
        .help("On-device Notebook Assistant")
      }
      .buttonStyle(AssistantControlStyle())
      .padding(.horizontal, 12)
      .frame(height: 52)
      .background(NotebookWindowDragRegion())
      if historyPresented {
        conversationHistory(compact: compact)
      } else {
        conversationThread(compact: compact)
        composer(compact: compact)
      }
    }
    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  private func conversationThread(compact: Bool) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
          if conversation.messages.isEmpty {
            welcome(compact: compact)
          }
          ForEach(conversation.messages) { message in
            VStack(alignment: .leading, spacing: 10) {
              Text(message.isUser ? localizedUI("You") : "Assistant")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              ForEach(message.attachments) { attachment in
                DisclosureGroup(localizedUI("Cell %ld", attachment.index)) {
                  Text(attachment.code).font(.callout.monospaced())
                    .textSelection(.enabled)
                }
              }
              ForEach(message.files) { file in
                Label(file.name, systemImage: file.kind.systemImage)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(message.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
              if let suggestion = message.suggestedEdit {
                suggestedEdit(suggestion, messageID: message.id)
              }
            }
            .padding(14)
            .background(
              message.isUser ? Color.accentColor.opacity(0.08) : Color.clear,
              in: RoundedRectangle(cornerRadius: 14))
          }
          if conversation.generating {
            ProgressView("Thinking…").controlSize(.small)
          }
          Color.clear.frame(height: 1).id("bottom")
        }
        .padding(compact ? 14 : 18)
      }
      .onChange(of: conversation.messages.count) { _, _ in
        proxy.scrollTo("bottom", anchor: .bottom)
      }
    }
  }

}
