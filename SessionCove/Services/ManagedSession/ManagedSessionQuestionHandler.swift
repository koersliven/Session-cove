import Foundation

/// Bridges the hook question flow to pty stdin injection for managed sessions.
///
/// When a managed session fires an AskUserQuestion hook event, the user
/// answers via Session Cove's UI (HookQuestionView). This handler converts
/// the structured answer payload into the exact terminal text that Claude
/// expects at its interactive prompt, then writes it directly to the
/// managed session's master fd.
///
/// Key insight (from claude-sessions / node-pty): writing to the pty master fd
/// is BUFFERED in the kernel. The child process (claude) reads from stdin when
/// ready — writes queue up in the kernel buffer until the child enters its
/// next read() call. This means we can write IMMEDIATELY on user submit with
/// no delay needed for simple cases. The only exception is the "Other" option
/// flow where Claude expects a two-step interaction (option index → prompt →
/// custom text), requiring a ~500ms gap between writes so Claude can transition
/// from "read option" to "read custom text" mode.
///
/// For non-managed sessions (user-owned iTerm), the existing
/// `TerminalTextInjector` path remains the primary delivery mechanism.
/// This handler is the managed-session equivalent — same answer-text
/// logic, different delivery channel (direct pty write vs. terminal adapter).
enum ManagedSessionQuestionHandler {

    // MARK: - Answer Delivery Classification

    /// Describes how a single question's answer should be delivered to the pty.
    private enum AnswerDelivery {
        /// Single write: text (index, comma-separated indices, or free text).
        /// Written immediately — kernel buffers until Claude reads.
        case immediate(String)
        /// Two-step "Other" flow: first write Other's 1-based index, then
        /// after ~500ms write the custom text. The delay gives Claude time
        /// to transition from option-selection mode to free-text input mode
        /// ("Type something:" prompt).
        case otherTwoStep(otherIndex: Int, customText: String)
    }

    // MARK: - Public API

    /// Deliver an answer to a managed session's AskUserQuestion prompt.
    ///
    /// Writes happen immediately (kernel-buffered) for simple option/text
    /// answers. For "Other" option flows, a Task schedules the custom text
    /// write after a 500ms delay so Claude can render its "Type something:"
    /// prompt before the text arrives.
    ///
    /// Handles ALL questions in the form sequentially (Claude presents them
    /// one after another in the terminal). For single-question forms (the
    /// common case), this collapses to a single synchronous write.
    ///
    /// - Parameters:
    ///   - sessionId: The managed session to write to.
    ///   - questions: The question descriptors from the hook payload.
    ///   - answers: Map of questionId -> user's answer (option id or free text).
    /// - Returns: `true` if the first write succeeded (subsequent writes are
    ///   scheduled asynchronously for multi-question or "Other" flows).
    @MainActor
    @discardableResult
    static func handleAnswer(
        sessionId: String,
        questions: [HookInterventionQuestion],
        answers: [String: String]
    ) -> Bool {
        let controller = ManagedSessionController.shared

        guard controller.isManaged(sessionId: sessionId) else {
            print("[ManagedSessionQuestionHandler] session \(sessionId.prefix(12)) is not managed, skipping")
            return false
        }

        // Build delivery plan for each question that has an answer.
        var deliveries: [(question: HookInterventionQuestion, delivery: AnswerDelivery)] = []
        for question in questions {
            guard let answer = answers[question.id], !answer.isEmpty else { continue }
            let delivery = classifyAnswer(question: question, answer: answer)
            deliveries.append((question, delivery))
        }

        guard !deliveries.isEmpty else {
            print("[ManagedSessionQuestionHandler] no deliverable answers for session \(sessionId.prefix(12))")
            return false
        }

        // Fast path: single question, immediate delivery — synchronous write.
        if deliveries.count == 1, case .immediate(let text) = deliveries[0].delivery {
            let success = controller.writeToSession(sessionId: sessionId, text: text)
            if success {
                print("[ManagedSessionQuestionHandler] delivered answer to session \(sessionId.prefix(12)): \"\(text.prefix(40))\"")
            } else {
                print("[ManagedSessionQuestionHandler] write failed for session \(sessionId.prefix(12))")
            }
            return success
        }

        // Complex path: multiple questions or "Other" two-step. Write the
        // first piece immediately (returns success/failure), then schedule
        // remaining writes in a Task with appropriate delays.
        let firstDelivery = deliveries[0].delivery
        let firstSuccess: Bool
        switch firstDelivery {
        case .immediate(let text):
            firstSuccess = controller.writeToSession(sessionId: sessionId, text: text)
        case .otherTwoStep(let otherIndex, _):
            firstSuccess = controller.writeToSession(sessionId: sessionId, text: String(otherIndex))
        }

        guard firstSuccess else {
            print("[ManagedSessionQuestionHandler] first write failed for session \(sessionId.prefix(12))")
            return false
        }

        // Schedule remaining writes (including the second part of a first-
        // question "Other" and all subsequent questions).
        Task { @MainActor in
            await deliverRemaining(
                sessionId: sessionId,
                deliveries: deliveries,
                controller: controller
            )
        }

        print("[ManagedSessionQuestionHandler] initiated delivery for \(deliveries.count) question(s) to session \(sessionId.prefix(12))")
        return true
    }

    // MARK: - Sequential Delivery

    /// Delivers the remaining parts of a multi-step answer sequence.
    /// Called after the first write already succeeded synchronously.
    @MainActor
    private static func deliverRemaining(
        sessionId: String,
        deliveries: [(question: HookInterventionQuestion, delivery: AnswerDelivery)],
        controller: ManagedSessionController
    ) async {
        for (idx, entry) in deliveries.enumerated() {
            switch entry.delivery {
            case .immediate(let text):
                // First delivery's immediate was already written synchronously.
                if idx == 0 { continue }
                // Subsequent questions: write immediately (kernel-buffered).
                controller.writeToSession(sessionId: sessionId, text: text)

            case .otherTwoStep(let otherIndex, let customText):
                if idx == 0 {
                    // First delivery: the otherIndex was already written.
                    // Wait 500ms then write the custom text.
                    try? await Task.sleep(for: .milliseconds(500))
                    controller.writeToSession(sessionId: sessionId, text: customText)
                } else {
                    // Subsequent question with "Other": write index, wait, write text.
                    controller.writeToSession(sessionId: sessionId, text: String(otherIndex))
                    try? await Task.sleep(for: .milliseconds(500))
                    controller.writeToSession(sessionId: sessionId, text: customText)
                }
            }
        }
    }

    // MARK: - Answer Classification

    /// Classify how a single question's answer should be delivered to the pty.
    ///
    /// - For free-text questions (no options): `.immediate(verbatim text)`.
    /// - For option-based questions where user selected known options:
    ///   `.immediate("1")` or `.immediate("1,3")`.
    /// - For "Other" flow (allowsOther + user typed custom text without
    ///   selecting a predefined option): `.otherTwoStep(otherIndex, customText)`.
    private static func classifyAnswer(
        question: HookInterventionQuestion,
        answer: String
    ) -> AnswerDelivery {
        // Free-text question (no options) — immediate verbatim write.
        if question.options.isEmpty {
            return .immediate(answer)
        }

        // Option-based question: answer contains comma-separated option IDs
        // (e.g. "us-east" or "api,ui") possibly with trailing custom text
        // when allowsOther is true.
        let selectedIds = answer.split(separator: ",").map(String.init)
        var indices: [Int] = []
        var customText: String?

        for selectedId in selectedIds {
            let trimmed = selectedId.trimmingCharacters(in: .whitespaces)
            if let idx = question.options.firstIndex(where: { $0.id == trimmed }) {
                indices.append(idx + 1) // 1-based
            } else {
                // Not a known option id — this is custom "Other" text.
                customText = trimmed
            }
        }

        // "Other" two-step: user typed custom text without selecting any
        // predefined option AND the question supports "Other". In Claude's
        // terminal UX, "Other" is the last numbered option (options.count + 1).
        // The flow is: type Other index → Claude shows "Type something:" →
        // type the custom text.
        if indices.isEmpty, let custom = customText, question.allowsOther {
            let otherIndex = question.options.count + 1
            return .otherTwoStep(otherIndex: otherIndex, customText: custom)
        }

        // User typed custom text but question doesn't have allowsOther
        // (shouldn't happen via the UI, but degrade gracefully).
        if indices.isEmpty, let custom = customText {
            return .immediate(custom)
        }

        // Normal option selection. If both an option AND custom text were
        // present (edge case: user selected an option and typed in Other
        // field), prioritize the option — Claude only accepts one answer
        // per single-select prompt.
        if indices.isEmpty {
            return .immediate(answer) // fallback: pass through verbatim
        }

        if question.allowsMultiple {
            return .immediate(indices.map(String.init).joined(separator: ","))
        } else {
            return .immediate(String(indices[0]))
        }
    }
}
