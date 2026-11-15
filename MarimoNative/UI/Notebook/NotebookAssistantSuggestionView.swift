import MarimoApplication
import SwiftUI

extension NotebookAssistantView {
  func suggestedEdit(
    _ suggestion: NotebookAssistantConversation.SuggestedEdit,
    messageID: UUID
  ) -> some View {
    let expanded = expandedSuggestionIDs.contains(messageID)
    let state = store.checkedCodeEditState(
      cellID: suggestion.cellID,
      expectedCode: suggestion.originalCode,
      replacementCode: suggestion.replacementCode
    )
    return VStack(alignment: .leading, spacing: 10) {
      Button {
        if expanded {
          expandedSuggestionIDs.remove(messageID)
        } else {
          expandedSuggestionIDs.insert(messageID)
        }
      } label: {
        HStack(spacing: 8) {
          Image(
            systemName: state == .alreadyApplied
              ? "checkmark.circle.fill" : "doc.text.magnifyingglass"
          )
          .foregroundStyle(state == .alreadyApplied ? Color.green : Color.accentColor)
          Text(
            state == .alreadyApplied
              ? localizedUI("Applied to Cell %ld", suggestion.cellIndex)
              : localizedUI("Review Changes to Cell %ld", suggestion.cellIndex)
          )
          .font(.callout.weight(.medium))
          Spacer(minLength: 0)
          Image(systemName: expanded ? "chevron.up" : "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(AssistantControlStyle())
      .accessibilityHint("Shows the original and proposed code before applying it.")

      if expanded {
        codePreview(
          title: localizedUI("Original"),
          code: suggestion.originalCode,
          color: .red
        )
        codePreview(
          title: localizedUI("Proposed"),
          code: suggestion.replacementCode,
          color: .green
        )
        if let reason = checkedEditReason(state) {
          Label(
            reason,
            systemImage: state == .alreadyApplied ? "checkmark.circle" : "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(state == .alreadyApplied ? Color.secondary : Color.orange)
        }
        HStack {
          Spacer()
          Button("Cancel") {
            expandedSuggestionIDs.remove(messageID)
          }
          .buttonStyle(AssistantControlStyle())
          Button("Apply to Cell", systemImage: "checkmark") {
            Task {
              let result = await store.applyCheckedCodeEdit(
                cellID: suggestion.cellID,
                expectedCode: suggestion.originalCode,
                replacementCode: suggestion.replacementCode
              )
              if result == .alreadyApplied {
                expandedSuggestionIDs.remove(messageID)
              }
            }
          }
          .buttonStyle(AssistantControlStyle(prominent: true))
          .disabled(state != .ready)
        }
      }
    }
    .padding(10)
    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
  }

  func codePreview(title: String, code: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: title == localizedUI("Original") ? "minus" : "plus")
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
      ScrollView([.horizontal, .vertical]) {
        Text(code.isEmpty ? localizedUI("Empty Code") : code)
          .font(.caption.monospaced())
          .textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 128)
      .padding(8)
      .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  func checkedEditReason(_ state: CheckedCodeEditState) -> String? {
    switch state {
    case .ready:
      nil
    case .alreadyApplied:
      localizedUI("This change has already been applied.")
    case .missingCell:
      localizedUI("The target cell no longer exists.")
    case .sourceChanged:
      localizedUI("The cell changed after this suggestion was generated.")
    case .textCell:
      localizedUI("Assistant changes currently support code cells only.")
    }
  }

  func conversationHistory(compact: Bool) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 10) {
        if conversation.history.isEmpty {
          ContentUnavailableView(
            "No Conversation History",
            systemImage: "clock.arrow.circlepath",
            description: Text("Start a new conversation to keep the current one in history.")
          )
          .frame(maxWidth: .infinity, minHeight: 280)
        } else {
          ForEach(conversation.history) { item in
            Button {
              conversation.restore(item)
              historyPresented = false
              promptFocused = true
            } label: {
              HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                  .foregroundStyle(.secondary)
                  .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 5) {
                  Text(item.title ?? localizedUI("Untitled Conversation"))
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                  HStack(spacing: 8) {
                    Text(
                      item.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    if !item.messages.isEmpty {
                      Text(localizedUI("%ld Messages", item.messages.count))
                    }
                    if item.contextCount > 0 {
                      Label(String(item.contextCount), systemImage: "paperclip")
                    }
                  }
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.tertiary)
              }
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
              .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(AssistantControlStyle())
            .accessibilityLabel(
              localizedUI(
                "Open Conversation: %@", item.title ?? localizedUI("Untitled Conversation"))
            )
          }
        }
      }
      .padding(compact ? 14 : 18)
    }
  }

  func welcome(compact: Bool) -> some View {
    let explanationPrompt = localizedUI("Explain what this cell does")
    return VStack(alignment: .leading, spacing: 24) {
      Image(systemName: "apple.intelligence")
        .font(.system(size: 28, weight: .light)).foregroundStyle(assistantGradient)
      Text("Let's talk about code.")
        .font(.system(size: compact ? 21 : 24, weight: .semibold))
      Text("Attach a cell, file, or image to add context to the conversation.")
        .font(.callout)
        .foregroundStyle(.secondary)
      ForEach(
        [explanationPrompt, localizedUI("Suggest improvements to this code")], id: \.self
      ) { prompt in
        Button {
          attachSelectedCell()
          conversation.draft = prompt
          promptFocused = true
        } label: {
          HStack(spacing: 12) {
            Image(
              systemName: prompt == explanationPrompt ? "text.magnifyingglass" : "wand.and.stars"
            )
            .foregroundStyle(.secondary)
            Text(prompt)
              .font(.callout)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(AssistantControlStyle())
      }
    }
    .padding(.vertical, compact ? 24 : 40)
  }

  func composer(compact: Bool) -> some View {
    let hasContext = !conversation.attachments.isEmpty || !conversation.fileAttachments.isEmpty
    return VStack(alignment: .leading, spacing: 12) {
      if let reason = unavailableReason {
        Label(reason, systemImage: "info.circle")
          .font(.callout).foregroundStyle(.secondary)
      }
      if let error = conversation.error {
        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
      }
      VStack(alignment: .leading, spacing: 0) {
        if !conversation.attachments.isEmpty || !conversation.fileAttachments.isEmpty {
          ScrollView {
            VStack(spacing: 8) {
              ForEach(conversation.attachments) { attachment in
                cellAttachmentChip(attachment)
              }
              ForEach(conversation.fileAttachments) { file in
                attachmentChip(
                  title: file.name,
                  detail: file.detail,
                  systemImage: file.kind.systemImage
                ) {
                  conversation.fileAttachments.removeAll { $0.id == file.id }
                }
              }
            }
          }.frame(
            height: min(
              112,
              CGFloat(conversation.attachments.count + conversation.fileAttachments.count) * 52
            )
          )
          .padding([.top, .horizontal], 12)
        }
        TextField("Ask Assistant…", text: $conversation.draft, axis: .vertical)
          .font(.system(size: 14))
          .lineSpacing(4)
          .lineLimit(
            hasContext ? 1...4 : (compact ? 3...6 : 4...8)
          )
          .textFieldStyle(.plain)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 16)
          .padding(.vertical, hasContext ? 8 : 16)
          .focused($promptFocused)
          .simultaneousGesture(
            TapGesture().onEnded {
              store.leaveEditor()
              promptFocused = true
            }
          )
          .accessibilityIdentifier("notebook.assistant.prompt")
          .disabled(conversation.generating)
        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        HStack(spacing: 8) {
          Button("Attach Files or Images", systemImage: "paperclip") {
            fileImporterPresented = true
            promptFocused = true
          }
          .labelStyle(.iconOnly)
          .help("Attach Files or Images")
          .buttonStyle(AssistantControlStyle())
          .disabled(conversation.generating)
          Button("Attach Selected Cell", systemImage: "chevron.left.forwardslash.chevron.right") {
            attachSelectedCell()
            promptFocused = true
          }
          .labelStyle(.iconOnly)
          .help("Attach Selected Cell")
          .buttonStyle(AssistantControlStyle())
          .disabled(store.document.selectedCellID == nil || conversation.generating)
          Spacer()
          ViewThatFits(in: .horizontal) {
            Text("Processed on This Mac")
            Image(systemName: "apple.logo").accessibilityLabel("Processed on This Mac")
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
          Button("Send", systemImage: "arrow.up") { conversation.send() }
            .labelStyle(.iconOnly)
            .buttonStyle(AssistantControlStyle(prominent: true))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(
              conversation.generating || unavailableReason != nil
                || conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .help("Send (⌘↩)")
        }
        .padding(8)
      }
      .background(
        Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : 0.92),
        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(
            assistantGradient.opacity(promptFocused ? 0.85 : 0.32),
            lineWidth: contrast == .increased ? 2 : 1
          )
          .allowsHitTesting(false)
      }
      .shadow(
        color: reduceTransparency ? .clear : .purple.opacity(promptFocused ? 0.12 : 0.04),
        radius: promptFocused ? 14 : 6, y: 2)
      Text("Changes apply only after review. Code is never run automatically.")
        .font(.caption2).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
    .padding(compact ? 12 : 18)
  }

  func attachmentChip(
    title: String, detail: String, systemImage: String, remove: @escaping () -> Void
  ) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: systemImage)
        .frame(width: 16)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.semibold).lineLimit(1)
        Text(detail).lineLimit(1).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button("Remove Attachment", systemImage: "xmark", action: remove)
        .labelStyle(.iconOnly)
        .buttonStyle(AssistantControlStyle())
    }
    .font(.caption)
    .padding(8)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  func cellAttachmentChip(_ attachment: NotebookAssistantConversation.Attachment) -> some View {
    let summary =
      attachment.code.split(whereSeparator: \.isNewline)
      .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .map(String.init) ?? localizedUI("Empty Code")
    return HStack(spacing: 10) {
      Image(systemName: "chevron.left.forwardslash.chevron.right")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(assistantGradient)
        .frame(width: 28, height: 28)
        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 3) {
        Text(localizedUI("Cell %ld", attachment.index))
          .font(.caption.weight(.semibold))
        Text(summary)
          .font(.caption2.monospaced())
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      AssistantAttachmentRemoveButton {
        conversation.attachments.removeAll { $0.id == attachment.id }
      }
    }
    .padding(.leading, 8)
    .padding(.trailing, 6)
    .padding(.vertical, 7)
    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    .overlay {
      RoundedRectangle(cornerRadius: 13)
        .strokeBorder(assistantGradient.opacity(0.18), lineWidth: 1)
        .allowsHitTesting(false)
    }
    .accessibilityElement(children: .contain)
  }

  var assistantGradient: LinearGradient {
    LinearGradient(
      colors: [.orange, .pink, .purple, .cyan],
      startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  func attachSelectedCell() {
    guard
      let index = store.document.cells.firstIndex(where: {
        $0.runtimeID == store.document.selectedCellID
      })
    else { return }
    conversation.attach(store.document.cells[index], index: index + 1)
  }

  var unavailableReason: String? {
    switch conversation.model.availability {
    case .available: nil
    case .unavailable(.deviceNotEligible):
      localizedUI("This Mac does not support Apple Intelligence.")
    case .unavailable(.appleIntelligenceNotEnabled):
      localizedUI("Turn on Apple Intelligence in System Settings to use the assistant.")
    case .unavailable(.modelNotReady):
      localizedUI("The on-device model is still being prepared. Try again later.")
    case .unavailable:
      localizedUI("Apple Intelligence is currently unavailable.")
    }
  }
}

private struct AssistantAttachmentRemoveButton: View {
  let remove: () -> Void
  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button("Remove Attachment", systemImage: "xmark", action: remove)
      .labelStyle(.iconOnly)
      .font(.system(size: 10, weight: .semibold))
      .frame(width: 26, height: 26)
      .foregroundStyle(.secondary)
      .background(
        Color.primary.opacity(hovering ? 0.1 : 0.035),
        in: Circle()
      )
      .contentShape(Circle())
      .buttonStyle(.plain)
      .onHover { hovering = $0 }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
      .help("Remove Attachment")
  }
}
