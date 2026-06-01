import SwiftUI

/// Pixel-styled equivalent of ping-island's `SessionQuestionForm`. Rendered in
/// place of `PermissionPingCard` / `HookApprovalPanel` whenever a
/// `HookPermissionRequest` has `kind == .question` (AskUserQuestion /
/// AskFollowupQuestion). Sized to live inside both the notch popping panel
/// (480×360) and the pet ping frame (388×360).
///
/// Single-select questions render the chosen option's id in `[String: String]`.
/// Multi-select questions join selected ids with ",". Free-text TextField /
/// SecureField answers go through verbatim. Empty answers are submitted as
/// empty strings so downstream `ClaudePermissionHook.resolve` still sees the
/// question id keys (CoveViewModel filters those server-side if needed).
struct HookQuestionView: View {
    let request: HookPermissionRequest
    let onSubmit: ([String: String]) -> Void
    let onCancel: () -> Void

    /// Selected option ids per question. For single-select, the array length is
    /// 0 or 1; for multi-select it can hold any subset of option ids.
    @State private var selectedOptionIds: [String: [String]] = [:]
    /// Free-text answer per question — used when the question has no options
    /// (plain TextField/SecureField) or when `allowsOther` is enabled.
    @State private var textAnswers: [String: String] = [:]

    var body: some View {
        PixelHUDPanel {
            VStack(alignment: .leading, spacing: 10) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(request.questions) { question in
                            questionSection(question)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 240)

                actionRow
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            CoveMascotView(state: .attention, scale: .approval)
            VStack(alignment: .leading, spacing: 3) {
                Text("Question from Claude")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                Text(request.toolName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(PixelPalette.alert)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func questionSection(_ question: HookInterventionQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(question.header.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(PixelPalette.alert)
                if question.allowsMultiple {
                    Text("MULTI")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(PixelPalette.alert.opacity(0.78))
                        )
                }
            }

            Text(question.prompt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let detail = question.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !question.options.isEmpty {
                optionsList(for: question)
                if question.allowsOther {
                    otherField(for: question)
                }
            } else if question.isSecret {
                secureField(for: question)
            } else {
                textField(for: question)
            }
        }
    }

    @ViewBuilder
    private func optionsList(for question: HookInterventionQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(question.options) { option in
                Button {
                    toggle(option.id, for: question)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        marker(question: question, optionId: option.id)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            if let detail = option.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                isSelected(optionId: option.id, for: question)
                                    ? PixelPalette.hudEdge.opacity(0.40)
                                    : Color.white.opacity(0.04)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        isSelected(optionId: option.id, for: question)
                                            ? PixelPalette.alert.opacity(0.75)
                                            : Color.white.opacity(0.14),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func marker(question: HookInterventionQuestion, optionId: String) -> some View {
        let selected = isSelected(optionId: optionId, for: question)
        Group {
            if question.allowsMultiple {
                // Pixel checkbox: square outline + filled square when selected.
                ZStack {
                    Rectangle()
                        .stroke(Color.white.opacity(selected ? 0.85 : 0.5), lineWidth: 1)
                    if selected {
                        Rectangle()
                            .fill(PixelPalette.alert)
                            .padding(2)
                    }
                }
                .frame(width: 11, height: 11)
            } else {
                // Pixel radio: outer square ring + inner filled pixel when selected.
                ZStack {
                    Rectangle()
                        .stroke(Color.white.opacity(selected ? 0.85 : 0.5), lineWidth: 1)
                    if selected {
                        Rectangle()
                            .fill(PixelPalette.alert)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 11, height: 11)
            }
        }
        .padding(.top, 1)
    }

    private func textField(for question: HookInterventionQuestion) -> some View {
        TextField("", text: textBinding(for: question))
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
    }

    private func secureField(for question: HookInterventionQuestion) -> some View {
        SecureField("", text: textBinding(for: question))
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
    }

    private func otherField(for question: HookInterventionQuestion) -> some View {
        TextField("Other...", text: textBinding(for: question))
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
    }

    private var actionRow: some View {
        HStack(spacing: 7) {
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.10))
                            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                onSubmit(submissionPayload())
            } label: {
                Text("Submit")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.04, green: 0.13, blue: 0.20))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.white.opacity(canSubmit ? 0.92 : 0.40))
                            .overlay(Capsule().stroke(.white.opacity(0.42), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    // MARK: - State helpers

    private func textBinding(for question: HookInterventionQuestion) -> Binding<String> {
        Binding(
            get: { textAnswers[question.id] ?? "" },
            set: { textAnswers[question.id] = $0 }
        )
    }

    private func isSelected(optionId: String, for question: HookInterventionQuestion) -> Bool {
        selectedOptionIds[question.id, default: []].contains(optionId)
    }

    private func toggle(_ optionId: String, for question: HookInterventionQuestion) {
        if question.allowsMultiple {
            var current = selectedOptionIds[question.id, default: []]
            if let idx = current.firstIndex(of: optionId) {
                current.remove(at: idx)
            } else {
                current.append(optionId)
            }
            selectedOptionIds[question.id] = current
        } else {
            selectedOptionIds[question.id] = [optionId]
        }
    }

    private var canSubmit: Bool {
        // Every question must contribute at least one piece of content
        // (an option, free text, or "other..." text).
        request.questions.allSatisfy { hasAnswer(for: $0) }
    }

    private func hasAnswer(for question: HookInterventionQuestion) -> Bool {
        let optionIds = selectedOptionIds[question.id, default: []]
        let text = (textAnswers[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !optionIds.isEmpty { return true }
        if !text.isEmpty { return true }
        return false
    }

    private func submissionPayload() -> [String: String] {
        var payload: [String: String] = [:]
        for question in request.questions {
            let optionIds = selectedOptionIds[question.id, default: []]
            let text = (textAnswers[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !question.options.isEmpty {
                // Selectable question: id list joined with ",", plus optional
                // "other..." text appended after a comma so the python hook can
                // reconstruct the user's intent.
                var parts = optionIds
                if question.allowsOther && !text.isEmpty {
                    parts.append(text)
                }
                payload[question.id] = parts.joined(separator: ",")
            } else {
                // Free-text or secret question: send the text verbatim.
                payload[question.id] = text
            }
        }
        return payload
    }
}
