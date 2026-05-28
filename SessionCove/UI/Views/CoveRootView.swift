import SwiftUI

struct CoveRootView: View {
    @Bindable var viewModel: CoveViewModel
    var onFrameSizeChange: ((CoveFrameSize) -> Void)? = nil

    var body: some View {
        contentView
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: viewModel.frameSize)
            .onChange(of: viewModel.frameSize) { _, newSize in
                onFrameSizeChange?(newSize)
            }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.frameSize {
        case .compact:
            CompactBarView(viewModel: viewModel)
                .frame(width: 300, height: 50)

        case .ping:
            pingView

        case .expanded:
            expandedView
                .frame(width: 500, height: 460)
                .padding(.top, 10)
        }
    }

    private var pingView: some View {
        VStack(spacing: 0) {
            CompactBarView(viewModel: viewModel)
                .frame(height: 50)
                .padding(.horizontal, 30)

            if let request = viewModel.pendingHookRequest {
                PermissionPingCard(request: request) { decision in
                    viewModel.decideHookRequest(decision)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
        }
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            switch viewModel.uiMode {
            case .compact, .permissionInterruption:
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
