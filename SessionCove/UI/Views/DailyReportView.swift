import SwiftUI
import WebKit

struct DailyReportView: View {
    @Bindable var viewModel: CoveViewModel
    @State private var htmlContent: String = ""

    private var report: DailyReport? {
        viewModel.currentReport
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.1))

            if viewModel.isGeneratingReport {
                loadingView
            } else if let report {
                ReportWebView(html: htmlContent)
                    .onAppear {
                        if htmlContent.isEmpty {
                            htmlContent = DailyReportGenerator.buildHTML(from: report)
                        }
                    }
                    .onChange(of: report.generatedAt) { _, _ in
                        if let r = viewModel.currentReport {
                            htmlContent = DailyReportGenerator.buildHTML(from: r)
                        }
                    }
            } else {
                emptyView
            }
        }
        .frame(minWidth: 560, minHeight: 500)
        .background(Color(red: 0.03, green: 0.06, blue: 0.12))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "water.waves")
                .font(.system(size: 16))
                .foregroundStyle(.cyan)

            Text("潮汐日报")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            if let report, report.isFallback {
                Text("离线数据")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange.opacity(0.15)))
            }

            Button {
                viewModel.generateDailyReport()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                    Text("重新生成")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.cyan.opacity(0.12))
                        .overlay(Capsule().stroke(.cyan.opacity(0.3), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGeneratingReport)

            historyMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
    }

    private var historyMenu: some View {
        Menu {
            let dates = DailyReportGenerator.listReportDates()
            if dates.isEmpty {
                Text("暂无历史日报")
            } else {
                ForEach(dates.prefix(14), id: \.self) { date in
                    Button(formatDate(date)) {
                        if let loaded = DailyReportGenerator.loadReport(for: date) {
                            viewModel.currentReport = loaded
                            htmlContent = DailyReportGenerator.buildHTML(from: loaded)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            Text("正在生成潮汐日报...")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text("claude 正在分析过去 24 小时的会话")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "water.waves")
                .font(.system(size: 36))
                .foregroundStyle(.cyan.opacity(0.3))
            Text("暂无日报")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Button {
                viewModel.generateDailyReport()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("生成今日日报")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.cyan.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.cyan.opacity(0.3), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd (EEE)"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - WKWebView wrapper

struct ReportWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
