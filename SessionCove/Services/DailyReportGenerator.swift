import Foundation

enum DailyReportGenerator {
    private static let reportsDir: String = {
        let path = NSHomeDirectory() + "/.session-cove/reports"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()

    @MainActor
    static func generate() async -> DailyReport {
        let sessionData = DailyReportCollector.collect()

        guard !sessionData.isEmpty else {
            return emptyReport()
        }

        // Aggregate token stats across all sessions
        var globalStats = DailyReport.TokenStats()
        for project in sessionData {
            for session in project.sessions {
                let s = session.tokenStats
                globalStats.apiCalls += s.apiCalls
                globalStats.totalInput += s.totalInput
                globalStats.totalOutput += s.totalOutput
                globalStats.totalCacheRead += s.totalCacheRead
                globalStats.totalCacheWrite += s.totalCacheWrite
                for (model, usage) in s.modelBreakdown {
                    var existing = globalStats.modelBreakdown[model] ?? DailyReport.TokenStats.ModelUsage()
                    existing.calls += usage.calls
                    existing.inputTokens += usage.inputTokens
                    existing.outputTokens += usage.outputTokens
                    globalStats.modelBreakdown[model] = existing
                }
            }
        }

        let prompt = buildPrompt(from: sessionData, stats: globalStats)

        do {
            let markdown = try await callClaude(prompt: prompt)
            var report = DailyReport(
                date: Date(),
                projects: buildProjectSummaries(from: sessionData),
                rawMarkdown: markdown,
                generatedAt: Date(),
                isFallback: false
            )
            report.tokenStats = globalStats
            saveReport(report)
            return report
        } catch {
            print("[DailyReportGenerator] claude failed: \(error), using fallback")
            let report = fallbackReport(from: sessionData, stats: globalStats)
            saveReport(report)
            return report
        }
    }

    static func todayReportExists() -> Bool {
        let path = reportPath(for: Date())
        return FileManager.default.fileExists(atPath: path)
    }

    static func loadTodayReport() -> DailyReport? {
        loadReport(for: Date())
    }

    static func loadReport(for date: Date) -> DailyReport? {
        let path = reportPath(for: date)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(DailyReport.self, from: data)
    }

    static func listReportDates() -> [Date] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: reportsDir) else {
            return []
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { formatter.date(from: String($0.dropLast(5))) }
            .sorted(by: >)
    }

    // MARK: - HTML generation

    static func buildHTML(from report: DailyReport) -> String {
        return buildHTML(from: report, markdown: report.rawMarkdown)
    }

    static func buildHTML(from report: DailyReport, markdown: String) -> String {
        let htmlBody = markdownToHTML(markdown)
        let statsHTML = buildTokenStatsHTML(report.tokenStats)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd (EEE)"
        df.locale = Locale(identifier: "zh_CN")
        let dateStr = df.string(from: report.date)
        let projectCount = report.projects.count
        let totalSessions = report.projects.reduce(0) { $0 + $1.sessionCount }
        let fallbackBadge = report.isFallback
            ? "<span style=\"background:#f0a02020;color:#f0a020;padding:2px 8px;border-radius:10px;font-size:11px\">⚠ 离线数据</span>"
            : ""

        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>潮汐日报 — \(dateStr)</title>
        <style>
        :root {
          --abyss: #040d1a; --deep: #071428; --ocean: #0c1f38;
          --surface: #122845; --shallow: #183355;
          --cyan: #5eeadb; --coral: #ff7875; --gold: #f5cd5c;
          --grass: #52d681; --sand: #d4b06a; --bubble: #89d4cf;
          --text: #c8dce8; --text-dim: #5e7a96; --text-bright: #eaf4fa;
          --card-bg: #0e1c30; --card-border: #1a3050;
          --reef: #2a1a3a;
        }
        * { margin:0; padding:0; box-sizing:border-box; }

        @keyframes float {
          0%,100% { transform:translateY(0) rotate(0deg); }
          25% { transform:translateY(-3px) rotate(1deg); }
          75% { transform:translateY(3px) rotate(-1deg); }
        }
        @keyframes bubble {
          0% { opacity:0; transform:translateY(10px) scale(0.5); }
          50% { opacity:0.5; }
          100% { opacity:0; transform:translateY(-30px) scale(1.2); }
        }
        @keyframes wave {
          0% { transform:translateX(0); }
          100% { transform:translateX(-60px); }
        }
        @keyframes glow {
          0%,100% { box-shadow:0 0 8px rgba(94,234,219,0.15); }
          50% { box-shadow:0 0 20px rgba(94,234,219,0.3); }
        }

        body {
          background: linear-gradient(180deg,
            var(--abyss) 0%,
            #06182e 15%,
            var(--deep) 30%,
            var(--ocean) 50%,
            #0e2440 70%,
            var(--shallow) 100%
          );
          color: var(--text);
          font-family: -apple-system,'SF Mono',Menlo,'PingFang SC',monospace;
          font-size:13px; line-height:1.75; min-height:100vh;
          position:relative; overflow-x:hidden;
        }

        /* Ocean depth lines */
        body::before {
          content:''; position:fixed; top:0; left:0; right:0; bottom:0; pointer-events:none; z-index:0;
          background:
            repeating-linear-gradient(0deg, transparent, transparent 80px, rgba(94,234,219,0.02) 80px, rgba(94,234,219,0.02) 81px),
            repeating-linear-gradient(0deg, transparent, transparent 200px, rgba(94,234,219,0.015) 200px, rgba(94,234,219,0.015) 201px);
        }

        .container { max-width:680px; margin:0 auto; padding:0 20px 80px; position:relative; z-index:1; }

        /* ── Island Header ── */
        .sky-island {
          text-align:center; padding:48px 20px 36px; margin:0 -20px 8px;
          position:relative;
          background:linear-gradient(180deg, transparent 50%, rgba(14,28,48,0.6) 100%);
        }
        .sky-island::after {
          content:''; display:block; width:200px; height:3px; margin:28px auto 0;
          background:linear-gradient(90deg, transparent, var(--cyan), transparent);
          border-radius:2px;
        }
        .island-icon {
          font-size:52px; margin-bottom:8px; animation:float 6s ease-in-out infinite;
          filter:drop-shadow(0 4px 12px rgba(94,234,219,0.25));
        }
        .sky-island h1 {
          font-size:24px; font-weight:900; color:var(--text-bright);
          letter-spacing:3px; margin-bottom:4px;
          text-shadow:0 2px 8px rgba(94,234,219,0.2);
        }
        .sky-island .subtitle {
          font-size:11px; color:var(--text-dim); letter-spacing:1px;
        }
        .treasure-stats {
          display:flex; justify-content:center; gap:32px; margin-top:20px;
        }
        .treasure-stats .chest {
          text-align:center; padding:10px 18px;
          background:var(--card-bg); border-radius:10px;
          border:2px solid var(--card-border);
          box-shadow:0 4px 16px rgba(0,0,0,0.3);
        }
        .treasure-stats .chest .num {
          font-size:22px; font-weight:900; color:var(--gold);
        }
        .treasure-stats .chest .label {
          font-size:10px; color:var(--text-dim); margin-top:2px;
        }

        /* ── Overview → Message in a Bottle ── */
        .bottle {
          background:linear-gradient(135deg, rgba(14,28,48,0.9), rgba(18,40,69,0.95));
          border:2px solid var(--card-border); border-radius:12px;
          padding:22px 26px; margin:24px 0 32px;
          position:relative; overflow:hidden;
          box-shadow:0 8px 32px rgba(0,0,0,0.25), inset 0 1px 0 rgba(255,255,255,0.03);
          border-left:4px solid var(--cyan);
        }
        .bottle::before {
          content:'📜'; position:absolute; right:16px; top:-4px; font-size:28px; opacity:0.15;
        }
        .bottle p { color:var(--text-bright); font-size:13px; }

        /* ── Wave Divider ── */
        .wave-divider {
          height:28px; margin:0 -20px; position:relative; overflow:hidden;
        }
        .wave-divider svg {
          position:absolute; bottom:0; width:200%; animation:wave 8s linear infinite;
        }

        /* ── Island Project Card ── */
        .island-card {
          background:var(--card-bg);
          border:2px solid var(--card-border);
          border-radius:14px 14px 10px 10px;
          padding:0 0 4px 0; margin-bottom:20px;
          overflow:hidden;
          box-shadow:0 6px 24px rgba(0,0,0,0.3);
          position:relative;
        }
        .island-card .reef-top {
          height:6px;
          background:linear-gradient(90deg, var(--grass), #3cb868, var(--grass));
          opacity:0.7;
        }
        .island-card .card-body {
          padding:14px 20px 18px;
        }
        .island-card h2 {
          font-size:15px; color:var(--grass); font-weight:900;
          margin-bottom:10px; display:flex; align-items:center; gap:8px;
        }
        .island-card h2 .octo { font-size:18px; }
        .island-card ul { list-style:none; padding-left:0; }
        .island-card ul li {
          padding:3px 0 3px 20px; position:relative; font-size:12px;
        }
        .island-card ul li::before {
          content:'▹'; position:absolute; left:2px; color:var(--cyan); font-size:10px;
        }
        .island-card .sand-line {
          height:3px; background:linear-gradient(90deg, transparent, var(--sand), transparent);
          opacity:0.5; margin:4px 20px 0;
        }

        /* ── Coral Focus Card ── */
        .coral-reef {
          background:linear-gradient(160deg, #1c0e24 0%, var(--reef) 40%, #1a1428 100%);
          border:2px solid #3d2250; border-radius:14px;
          padding:20px 24px; margin:28px 0 36px;
          position:relative; overflow:hidden;
          box-shadow:0 8px 32px rgba(100,30,60,0.15);
          border-left:4px solid var(--coral);
        }
        .coral-reef::before {
          content:'🪸'; position:absolute; right:20px; top:8px; font-size:26px; opacity:0.25;
        }
        .coral-reef::after {
          content:''; position:absolute; bottom:0; left:20%; right:20%; height:2px;
          background:linear-gradient(90deg, transparent, rgba(255,120,117,0.4), transparent);
        }
        .coral-reef h2 {
          font-size:15px; color:var(--coral); font-weight:900;
          margin-bottom:12px; letter-spacing:1px;
        }
        .coral-reef ul { list-style:none; padding-left:0; }
        .coral-reef ul li {
          padding:5px 0 5px 22px; position:relative; font-size:12px;
        }
        .coral-reef ul li::before {
          content:'✦'; position:absolute; left:2px; color:var(--coral); font-size:8px; top:7px;
        }

        /* ── Section Title ── */
        .section-title {
          display:flex; align-items:center; gap:10px;
          font-size:14px; font-weight:900; color:var(--gold);
          letter-spacing:2px; margin:28px 0 14px 4px;
        }
        .section-title .line {
          flex:1; height:2px; border-radius:1px;
          background:linear-gradient(90deg, var(--gold), transparent);
        }
        .section-title .fish { font-size:16px; }

        /* ── Bubbles ── */
        .bubbles { position:relative; height:0; }
        .bubble {
          position:absolute; width:6px; height:6px;
          background:radial-gradient(circle at 30% 30%, rgba(180,230,230,0.6), transparent);
          border-radius:50%; animation:bubble 4s ease-in infinite;
        }

        /* ── Token Stats Dashboard ── */
        .token-dash {
          background:linear-gradient(160deg, #0a1628 0%, var(--card-bg) 50%, #0d1c32 100%);
          border:2px solid var(--card-border); border-radius:14px;
          padding:20px 24px 16px; margin:8px 0 20px;
          box-shadow:0 8px 32px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.02);
        }
        .token-dash .dash-title {
          font-size:11px; font-weight:900; color:var(--gold); letter-spacing:2px;
          margin-bottom:16px; display:flex; align-items:center; gap:6px;
        }
        .token-dash .dash-title::after {
          content:''; flex:1; height:1px;
          background:linear-gradient(90deg, var(--gold), transparent);
        }
        .token-row {
          display:flex; gap:16px; flex-wrap:wrap; justify-content:center;
          margin-bottom:14px;
        }
        .token-metric {
          text-align:center; min-width:64px;
          padding:8px 12px; border-radius:8px;
          background:rgba(0,0,0,0.2);
        }
        .token-metric .num {
          font-size:20px; font-weight:900;
        }
        .token-metric .tag {
          font-size:8px; color:var(--text-dim); letter-spacing:1px; margin-top:3px;
        }
        .token-bar-wrap {
          margin-top:4px;
        }
        .token-bar-wrap .labels {
          display:flex; justify-content:space-between;
          font-size:8px; color:var(--text-dim); margin-bottom:4px;
        }
        .token-bar {
          height:10px; border-radius:5px; overflow:hidden;
          display:flex; background:rgba(0,0,0,0.3);
        }
        .token-bar .seg { height:100%; transition:width 0.5s; }
        .token-bar .seg.in { background:linear-gradient(90deg, #2a6496, #4a9fd4); }
        .token-bar .seg.cache { background:linear-gradient(90deg, #1a7a4a, #3cba72); }
        .token-bar .seg.out { background:linear-gradient(90deg, #b8860b, #f0c040); }
        .model-table {
          margin-top:14px; border-top:1px solid var(--card-border); padding-top:10px;
        }
        .model-row {
          display:flex; align-items:center; gap:12px;
          padding:4px 8px; font-size:10px;
        }
        .model-row .model-name {
          color:var(--text-bright); font-weight:700; min-width:60px;
        }
        .model-row .model-tokens {
          color:var(--text-dim); min-width:60px; text-align:right;
        }
        .model-row .model-pct {
          color:var(--text-dim); min-width:32px; text-align:right; font-size:9px;
        }
        .model-row .model-cost {
          color:var(--coral); min-width:48px; text-align:right; font-weight:700;
        }

        /* ── Footer ── */
        .seabed {
          text-align:center; padding:40px 0 30px; position:relative;
        }
        .seabed .kelp {
          font-size:40px; letter-spacing:12px; opacity:0.15;
          animation:float 8s ease-in-out infinite;
        }
        .seabed .message {
          font-size:10px; color:var(--text-dim); margin-top:8px; letter-spacing:1px;
        }

        /* Shared */
        hr { border:none; border-top:1px solid var(--card-border); margin:16px 0; }
        p { margin:6px 0; }
        strong { color:var(--text-bright); font-weight:700; }
        code {
          background:rgba(0,0,0,0.3); padding:1px 7px; border-radius:4px;
          font-size:11px; border:1px solid var(--card-border);
        }
        blockquote {
          border-left:3px solid var(--gold); padding:4px 14px;
          margin:8px 0; color:var(--text-dim); font-style:italic;
          background:rgba(0,0,0,0.15); border-radius:0 6px 6px 0;
        }
        h3 { color:var(--text-bright); font-size:13px; margin-top:18px; margin-bottom:6px; }
        h4 { color:var(--text-dim); font-size:12px; margin-top:12px; margin-bottom:4px; }
        </style></head>
        <body>
        <div class="container">

        <!-- Island Header -->
        <div class="sky-island">
          <div class="island-icon">🏝️</div>
          <h1>潮 汐 日 报</h1>
          <div class="subtitle">\(dateStr) · \(projectCount) 个项目 · 共 \(totalSessions) 个会话 \(fallbackBadge)</div>
          <div class="treasure-stats">
            <div class="chest"><div class="num">\(projectCount)</div><div class="label">🏝️ 项目岛屿</div></div>
            <div class="chest"><div class="num">\(totalSessions)</div><div class="label">🐚 会话珍珠</div></div>
          </div>
        </div>

        <!-- Bubbles -->
        <div class="bubbles">
          <div class="bubble" style="left:10%;animation-delay:0s"></div>
          <div class="bubble" style="left:30%;animation-delay:1.5s;width:4px;height:4px"></div>
          <div class="bubble" style="left:55%;animation-delay:0.8s;width:8px;height:8px"></div>
          <div class="bubble" style="left:75%;animation-delay:2.2s;width:5px;height:5px"></div>
          <div class="bubble" style="left:90%;animation-delay:3s;width:3px;height:3px"></div>
        </div>

        <!-- Wave -->
        <div class="wave-divider">
          <svg viewBox="0 0 1200 28" preserveAspectRatio="none">
            <path d="M0,14 C150,28 300,0 450,14 C600,28 750,0 900,14 C1050,28 1200,0 1350,14 L1350,28 L0,28 Z" fill="var(--ocean)" opacity="0.4"/>
            <path d="M0,20 C200,10 400,30 600,20 C800,10 1000,30 1200,20 L1200,28 L0,28 Z" fill="var(--deep)" opacity="0.6"/>
          </svg>
        </div>

        \(statsHTML)

        \(htmlBody)

        <!-- Seabed -->
        <div class="seabed">
          <div class="kelp">🪸 🐚 🫧 🐠</div>
          <div class="message">Session Cove · 潮汐日报 · 每日自动生成</div>
        </div>

        </div></body></html>
        """
    }

    // MARK: - Private

    private static func markdownToHTML(_ md: String) -> String {
        var html = ""
        var inList = false
        var inBlockquote = false
        var inIsland = false      // inside an island-card
        var inBottle = false      // inside overview bottle
        var inReef = false        // inside coral-reef
        var pendingSection = ""   // section title before island card content

        func closeAll() {
            if inList { html += "</ul>\n"; inList = false }
            if inBlockquote { html += "</blockquote>\n"; inBlockquote = false }
            if inIsland { html += "<div class=\"sand-line\"></div></div></div>\n"; inIsland = false }
            if inBottle { html += "</div>\n"; inBottle = false }
            if inReef { html += "</div>\n"; inReef = false }
            pendingSection = ""
        }

        for line in md.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if inList { html += "</ul>\n"; inList = false }
                if inBlockquote { html += "</blockquote>\n"; inBlockquote = false }
                continue
            }

            // Code blocks
            if trimmed.hasPrefix("```") { continue }

            // ── H1: overview / 明日关注 ──
            if trimmed.hasPrefix("# ") {
                closeAll()
                let text = String(trimmed.dropFirst(2))

                if text.contains("总览") || text.contains("概") {
                    html += "<div class=\"bottle\"><p>"
                    inBottle = true
                    continue
                }
                if text.contains("关注") || text.contains("待办") || text.contains("建议") {
                    html += "<div class=\"coral-reef\"><h2>⚡ \(escapeHTML(text))</h2>\n"
                    inReef = true
                    continue
                }
                html += "<div class=\"bottle\"><p>"
                inBottle = true
                continue
            }

            // ── H2: project name → island card ──
            if trimmed.hasPrefix("## ") {
                closeAll()
                pendingSection = String(trimmed.dropFirst(3))
                continue
            }

            // ── H3: sub-section within card ──
            if trimmed.hasPrefix("### ") {
                if inBottle { html += "</p>" }
                let text = String(trimmed.dropFirst(4))
                // Open island card if we have a pending section
                if !inIsland && !pendingSection.isEmpty {
                    html += "<div class=\"section-title\"><span class=\"fish\">🐙</span><span>\(escapeHTML(pendingSection))</span><span class=\"line\"></span></div>\n"
                    html += "<div class=\"island-card\"><div class=\"reef-top\"></div><div class=\"card-body\">\n"
                    inIsland = true
                    pendingSection = ""
                }
                if inIsland || inReef || inBottle {
                    html += "<h3>\(escapeHTML(text))</h3>\n"
                } else {
                    html += "<h3>\(escapeHTML(text))</h3>\n"
                }
                continue
            }

            // ── H4 ──
            if trimmed.hasPrefix("#### ") {
                let text = String(trimmed.dropFirst(5))
                html += "<h4>\(escapeHTML(text))</h4>\n"
                continue
            }

            // ── Blockquote ──
            if trimmed.hasPrefix("> ") || trimmed.hasPrefix(">") {
                if !inBlockquote { html += "<blockquote>\n"; inBlockquote = true }
                let txt = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : String(trimmed.dropFirst(1))
                html += "<p>\(boldToHTML(escapeHTML(txt)))</p>\n"
                continue
            } else if inBlockquote {
                html += "</blockquote>\n"; inBlockquote = false
            }

            // ── List items ──
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList { html += "<ul>\n"; inList = true }
                let text = boldToHTML(escapeHTML(String(trimmed.dropFirst(2))))

                // If we have a pending section, open island card now
                if !inIsland && !pendingSection.isEmpty {
                    html += "<div class=\"section-title\"><span class=\"fish\">🐙</span><span>\(escapeHTML(pendingSection))</span><span class=\"line\"></span></div>\n"
                    html += "<div class=\"island-card\"><div class=\"reef-top\"></div><div class=\"card-body\">\n"
                    inIsland = true
                    pendingSection = ""
                }
                html += "<li>\(text)</li>\n"
                continue
            }

            if let firstChar = trimmed.first, firstChar.isNumber,
               trimmed.dropFirst().hasPrefix(". ") {
                if !inList { html += "<ul>\n"; inList = true }
                let dotIdx = trimmed.firstIndex(of: ".")!
                let text = boldToHTML(escapeHTML(String(trimmed[trimmed.index(dotIdx, offsetBy: 2)...])))
                html += "<li>\(text)</li>\n"
                continue
            }

            // ── Paragraph ──
            if inBottle {
                html += "\(boldToHTML(escapeHTML(trimmed)))<br>"
            } else {
                if inList { html += "</ul>\n"; inList = false }
                if inBlockquote { html += "</blockquote>\n"; inBlockquote = false }
                html += "<p>\(boldToHTML(escapeHTML(trimmed)))</p>\n"
            }
        }

        closeAll()
        return html
    }

    // MARK: - Token stats HTML

    private static func buildTokenStatsHTML(_ stats: DailyReport.TokenStats) -> String {
        guard stats.apiCalls > 0 else { return "" }

        let total = stats.totalInput + stats.totalOutput
        let cacheRate = stats.totalInput > 0
            ? stats.totalCacheRead * 100 / stats.totalInput
            : 0
        let freshInput = stats.totalInput - stats.totalCacheRead - stats.totalCacheWrite
        let freshPct = total > 0 ? freshInput * 100 / total : 0
        let cachePct = total > 0 ? stats.totalCacheRead * 100 / total : 0
        let outputPct = total > 0 ? stats.totalOutput * 100 / total : 0
        let cost = stats.estimatedCostUSD

        // Per-model rows
        var modelRows = ""
        let sortedModels = stats.modelBreakdown.sorted { $0.value.inputTokens + $0.value.outputTokens > $1.value.inputTokens + $1.value.outputTokens }
        for (model, usage) in sortedModels {
            let mTotal = usage.inputTokens + usage.outputTokens
            let mCost = DailyReport.TokenStats.costFor(input: usage.inputTokens, output: usage.outputTokens, model: model)
            let mPct = total > 0 ? mTotal * 100 / total : 0
            modelRows += """
            <div class="model-row">
            <span class="model-name">\(model)</span>
            <span class="model-tokens">\(formatNum(mTotal))</span>
            <span class="model-pct">\(mPct)%</span>
            <span class="model-cost">$\(String(format:"%.2f", mCost))</span>
            </div>
            """
        }

        return """
        <div class="token-dash">
        <div class="dash-title">📊 Token 用量总览</div>
        <div class="token-row">
        <div class="token-metric"><div class="num" style="color:var(--cyan)">\(formatNum(stats.apiCalls))</div><div class="tag">API 调用</div></div>
        <div class="token-metric"><div class="num" style="color:var(--text-bright)">\(formatNum(total))</div><div class="tag">总 Token</div></div>
        <div class="token-metric"><div class="num" style="color:var(--gold)">\(formatNum(stats.totalOutput))</div><div class="tag">输出 Token</div></div>
        <div class="token-metric"><div class="num" style="color:var(--grass)">\(cacheRate)%</div><div class="tag">缓存命中率</div></div>
        <div class="token-metric"><div class="num" style="color:var(--coral)">$\(String(format:"%.2f", cost))</div><div class="tag">等效 API 费用</div></div>
        </div>
        <div class="token-bar-wrap">
        <div class="labels"><span>🆕 新输入 \(formatNum(max(0,freshInput)))</span><span>💾 缓存命中 \(formatNum(stats.totalCacheRead))</span><span>✍️ 输出 \(formatNum(stats.totalOutput))</span></div>
        <div class="token-bar">
        <div class="seg in" style="width:\(max(1,freshPct))%"></div>
        <div class="seg cache" style="width:\(max(1,cachePct))%"></div>
        <div class="seg out" style="width:\(max(1,outputPct))%"></div>
        </div>
        </div>
        <div class="model-table">
        \(modelRows)
        </div>
        </div>
        """
    }

    private static func formatNum(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func boldToHTML(_ text: String) -> String {
        // Convert **bold** and __bold__ to <strong>
        var result = text
        for delimiter in ["**", "__"] {
            while let start = result.range(of: delimiter) {
                guard let end = result[start.upperBound...].range(of: delimiter) else { break }
                let inner = String(result[start.upperBound..<end.lowerBound])
                let replacement = "<strong>\(inner)</strong>"
                let fullRange = start.lowerBound..<end.upperBound
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        return result
    }

    // MARK: - Prompt

    private static func buildPrompt(from data: [ReportSessionData], stats: DailyReport.TokenStats) -> String {
        var lines: [String] = []
        lines.append("你是一个工作日报助手。请根据以下 Claude Code 的完整会话记录，深度分析用户今天做了什么。")
        lines.append("")
        lines.append("## 分析要求")
        lines.append("")
        lines.append("用「总-分-总」结构输出日报：")
        lines.append("")
        lines.append("### 结构")
        lines.append("```")
        lines.append("# 今日总览")
        lines.append("用一段话概括今天所有项目的整体工作主题和关键进展。")
        lines.append("")
        lines.append("## 项目名称 A")
        lines.append("### 完成事项")
        lines.append("- 具体事项")
        lines.append("### 进行中")
        lines.append("- 未完成事项")
        lines.append("")
        lines.append("## 项目名称 B")
        lines.append("...")
        lines.append("")
        lines.append("# 明日关注")
        lines.append("- 明天应该做的事")
        lines.append("- 风险或阻塞点")
        lines.append("```")
        lines.append("")
        lines.append("### 规则")
        lines.append("- 每个事项要具体，不要笼统：\"修复了 pet 滑块不缩放图片的 bug\" 比 \"修了 bug\" 好")
        lines.append("- 语义理解用户消息，提取实际完成的功能和决策")
        lines.append("- 「明日关注」要基于今天未完成的事项来推断")
        lines.append("- 输出纯 Markdown，不要额外解释")
        lines.append("")
        lines.append("## Token 用量统计")
        lines.append("")
        lines.append("API 调用次数: \(stats.apiCalls)")
        lines.append("总输入 token: \(stats.totalInput)")
        lines.append("总输出 token: \(stats.totalOutput)")
        lines.append("缓存命中: \(stats.totalCacheRead) token")
        lines.append("缓存写入: \(stats.totalCacheWrite) token")
        lines.append("")
        lines.append("请在日报中简要评价 token 使用效率。")
        lines.append("")
        lines.append("---")
        lines.append("")

        for project in data {
            let totalMsgCount = project.sessions.reduce(0) { $0 + $1.messageCount }
            lines.append("## \(project.projectName)")
            lines.append("路径: \(project.path) | 消息: ~\(totalMsgCount)")
            lines.append("")

            for (i, session) in project.sessions.enumerated() {
                if let title = session.aiTitle, !title.isEmpty {
                    lines.append("### 会话 \(i + 1) — \(title)")
                } else {
                    lines.append("### 会话 \(i + 1) (\(session.messageCount) 条消息)")
                }
                if let ts = session.timestamp {
                    lines.append("时间: \(ISO8601DateFormatter().string(from: ts))")
                }
                if let branch = session.gitBranch {
                    lines.append("分支: \(branch)")
                }

                if !session.userMessages.isEmpty {
                    lines.append("")
                    for msg in session.userMessages {
                        lines.append("- \(msg)")
                    }
                }

                if !session.assistantOutcomes.isEmpty {
                    lines.append("")
                    lines.append("关键回复:")
                    for outcome in session.assistantOutcomes.prefix(4) {
                        lines.append("> \(String(outcome.prefix(250)))")
                    }
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Claude

    private static func callClaude(prompt: String) async throws -> String {
        let claudePath = try findClaudeBinary()

        // Write prompt to temp file to avoid pipe buffer limits (16KB)
        let tmpDir = NSTemporaryDirectory()
        let promptFile = "\(tmpDir)/sc-daily-report-prompt-\(UUID().uuidString).txt"
        guard FileManager.default.createFile(atPath: promptFile, contents: prompt.data(using: .utf8)) else {
            throw ReportError.claudeFailed("failed to write prompt temp file")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "cat '\(promptFile)' | '\(claudePath)' --print"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let timeoutSeconds: TimeInterval = 180
                let deadline = Date().addingTimeInterval(timeoutSeconds)

                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.5)
                }

                if process.isRunning {
                    process.terminate()
                    try? FileManager.default.removeItem(atPath: promptFile)
                    continuation.resume(throwing: ReportError.timeout)
                    return
                }

                guard process.terminationStatus == 0 else {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "unknown error"
                    try? FileManager.default.removeItem(atPath: promptFile)
                    continuation.resume(throwing: ReportError.claudeFailed(errStr))
                    return
                }

                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                try? FileManager.default.removeItem(atPath: promptFile)
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
        }
    }

    private static func findClaudeBinary() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        if let _ = try? process.run() {
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        }

        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSHomeDirectory() + "/.claude/local/claude"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw ReportError.claudeNotFound
    }

    // MARK: - Fallback & summaries

    private static func buildProjectSummaries(from data: [ReportSessionData]) -> [DailyReport.ProjectSummary] {
        data.map { project in
            let timestamps = project.sessions.compactMap(\.timestamp) + project.sessions.map(\.lastModified)
            let branches = Set(project.sessions.compactMap(\.gitBranch))
            let highlights = project.sessions.compactMap(\.aiTitle)
            return DailyReport.ProjectSummary(
                projectName: project.projectName,
                path: project.path,
                sessionCount: project.sessions.count,
                firstActivity: timestamps.min() ?? Date(),
                lastActivity: timestamps.max() ?? Date(),
                highlights: highlights,
                gitBranches: Array(branches)
            )
        }
    }

    private static func fallbackReport(from data: [ReportSessionData], stats: DailyReport.TokenStats) -> DailyReport {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var markdown = "# 今日总览\n\n"
        markdown += "> ⚠️ AI 总结生成失败，以下为原始数据摘要\n\n"

        for project in data {
            let totalMsgs = project.sessions.reduce(0) { $0 + $1.messageCount }
            markdown += "## \(project.projectName)\n\n"
            markdown += "**\(project.sessions.count) 个会话 · ~\(totalMsgs) 条消息**\n\n"
            markdown += "### 完成事项\n\n"
            for session in project.sessions {
                if let title = session.aiTitle, !title.isEmpty {
                    markdown += "- \(title)\n"
                } else if !session.userMessages.isEmpty {
                    markdown += "- \(session.userMessages.first!)\n"
                }
            }
            markdown += "\n"
        }

        markdown += "# 明日关注\n\n- 请重新生成日报获取 AI 分析\n"

        var report = DailyReport(
            date: Date(),
            projects: buildProjectSummaries(from: data),
            rawMarkdown: markdown,
            generatedAt: Date(),
            isFallback: true
        )
        report.tokenStats = stats
        return report
    }

    private static func emptyReport() -> DailyReport {
        DailyReport(
            date: Date(),
            projects: [],
            rawMarkdown: "# 潮汐日报\n\n今日暂无活跃会话记录。\n\n# 明日关注\n\n新的一天，开始写代码吧！",
            generatedAt: Date(),
            isFallback: true
        )
    }

    // MARK: - Persistence

    private static func saveReport(_ report: DailyReport) {
        let jsonPath = reportPath(for: report.date)
        let mdPath = jsonPath.replacingOccurrences(of: ".json", with: ".md")
        let htmlPath = jsonPath.replacingOccurrences(of: ".json", with: ".html")

        if let jsonData = try? JSONEncoder().encode(report) {
            FileManager.default.createFile(atPath: jsonPath, contents: jsonData)
        }
        if let mdData = report.rawMarkdown.data(using: .utf8) {
            FileManager.default.createFile(atPath: mdPath, contents: mdData)
        }
        if let htmlData = buildHTML(from: report).data(using: .utf8) {
            FileManager.default.createFile(atPath: htmlPath, contents: htmlData)
        }
    }

    private static func reportPath(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(reportsDir)/\(formatter.string(from: date)).json"
    }

    enum ReportError: Error {
        case claudeNotFound
        case claudeFailed(String)
        case timeout
    }
}
