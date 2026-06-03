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
            // Width matches PetPlacementStrategy (petSize + pingCardWidth);
            // height kind-aware (approval=72/240, question=360,
            // completion=120). The .onChange at the top of body re-emits
            // onFrameSizeChange whenever pingHeight shifts so the panel
            // resizes mid-popping when the chevron toggles.
            pingView
                .frame(
                    width: PetPlacementStrategy.petSize.width + PetPlacementStrategy.pingCardWidth,
                    height: viewModel.pingHeight
                )

        case .expanded:
            // Fill the entire hostingView (= panel size). With the prior
            // .frame(500,460) + .padding(.top, 10) layout, SwiftUI
            // rendered into a 500×470 inset and the surrounding 20×10pt
            // of transparent panel edge produced a visual "rectangular
            // residue at all four corners" — clipShape only rounded the
            // SwiftUI content, but the panel's transparent margin still
            // looked square against the desktop. Filling the panel makes
            // the rounded clip land on the actual panel edge.
            expandedView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .clipShape(RoundedRectangle(cornerRadius: 18))
        // No .shadow / no outer stroke. The panel is borderless + .clear,
        // so SwiftUI's drop-shadow has no host space outside the panel
        // and gets clipped — that produced the dark "halo at four
        // corners" the user reported. Likewise an outer stroke only
        // shows up along the corner curvature and reads as a thin grey
        // ring against a low-contrast desktop. The flat clip is enough.
    }
}
