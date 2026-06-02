import SwiftUI

struct CoveRootView: View {
    @Bindable var viewModel: CoveViewModel
    var onFrameSizeChange: ((CoveFrameSize) -> Void)? = nil

    var body: some View {
        contentView
            .onChange(of: viewModel.frameSize) { _, newSize in
                onFrameSizeChange?(newSize)
            }
            // pingHeight depends on pendingHookRequest?.kind + approvalExpanded.
            // frameSize stays `.ping` across kind transitions and chevron toggles,
            // so onChange(of: frameSize) wouldn't fire — re-emit the callback
            // here so PetWindowController.updatePanelFrame re-computes the
            // NSPanel size with the new pingHeightOverride.
            .onChange(of: viewModel.pingHeight) { _, _ in
                if viewModel.frameSize == .ping {
                    onFrameSizeChange?(.ping)
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.frameSize {
        case .pet:
            PetMascotView(viewModel: viewModel)
                .frame(width: 48, height: 48)

        case .compact:
            CompactBarView(viewModel: viewModel)
                .frame(width: 300, height: 50)

        case .ping:
            // Height comes from viewModel.pingHeight — kind-aware
            // (approval=72/240, question=360, completion=120) so the same
            // ping frame hosts every hook flavor without new CoveFrameSize
            // cases. The .onChange listener at the top of body re-emits
            // onFrameSizeChange whenever pingHeight shifts.
            pingView
                .frame(width: 388, height: viewModel.pingHeight)

        case .expanded:
            expandedView
                .frame(width: 500, height: 460)
                .padding(.top, 10)
        }
    }

    private var pingView: some View {
        HStack(spacing: 0) {
            if viewModel.pingExpandDirection == .trailing {
                petInPing
                pingCardContent
            } else {
                pingCardContent
                petInPing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.03, green: 0.08, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    private var petInPing: some View {
        CoveMascotView(state: .attention, scale: .pet, grounded: false)
            .frame(width: 48, height: 48)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var pingCardContent: some View {
        if let request = viewModel.pendingHookRequest {
            switch request.kind {
            case .approval:
                PermissionPingCard(
                    request: request,
                    isExpanded: Binding(
                        get: { viewModel.approvalExpanded },
                        set: { viewModel.approvalExpanded = $0 }
                    )
                ) { decision in
                    viewModel.decideHookRequest(decision)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            case .question:
                HookQuestionView(
                    request: request,
                    onSubmit: { answers in
                        viewModel.decideHookRequest(.answer(answers: answers))
                    },
                    onCancel: {
                        viewModel.decideHookRequest(.deny)
                    }
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            case .completion:
                CompletionPingCard(
                    request: request,
                    resolvedSession: viewModel.findSession(byId: request.sessionId ?? "")
                ) { decision in
                    viewModel.decideHookRequest(decision)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            switch viewModel.uiMode {
            case .pet, .compact, .permissionInterruption:
                CompactBarView(viewModel: viewModel)
            case .harborOverview:
                HarborMapOverviewView(viewModel: viewModel)
            case .projectIsland:
                HarborMapOverviewView(viewModel: viewModel)
            case .sessionFocus:
                if let session = viewModel.selectedSession {
                    SessionDetailView(session: session, viewModel: viewModel)
                } else {
                    HarborMapOverviewView(viewModel: viewModel)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}
