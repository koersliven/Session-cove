import SwiftUI

struct CoveRootView: View {
    @Bindable var viewModel: CoveViewModel

    var body: some View {
        Group {
            if viewModel.isExpanded {
                expandedView
            } else {
                compactView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactView: some View {
        CompactBarView(viewModel: viewModel)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            switch viewModel.uiMode {
            case .compact:
                CompactBarView(viewModel: viewModel)
            case .harborOverview:
                CoveMapView(viewModel: viewModel)
            case .projectIsland:
                if let island = viewModel.selectedIsland {
                    IslandSessionListView(island: island, viewModel: viewModel)
                } else {
                    CoveMapView(viewModel: viewModel)
                }
            case .sessionFocus:
                if let session = viewModel.selectedSession {
                    SessionDetailView(session: session, viewModel: viewModel)
                } else {
                    CoveMapView(viewModel: viewModel)
                }
            case .permissionInterruption:
                PermissionInterruptionView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }
}
