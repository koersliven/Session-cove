import Foundation

/// A `(providerId, cwd)` pair: an enabled provider's agent binary is currently
/// running with the given working directory. `applyStatuses` uses this so the
/// match between a running process and an island is scoped to the island's
/// owning provider — a `claude` process at `/Users/foo` should activate only
/// the Claude island at `/Users/foo`, not (e.g.) a future Qoder island sharing
/// the same path.
struct ActiveAgentLocation: Hashable, Sendable {
    let providerId: String
    let cwd: String
}

final class ProcessDetector: @unchecked Sendable {
    static let shared = ProcessDetector()

    /// Backward-compatible — collects cwds of any enabled agent's running
    /// processes, ignoring provider attribution. Prefer
    /// `detectActiveAgentLocations()` for multi-provider correctness.
    /// If the user kills the agent, the session stops being active — they
    /// re-RESUME.
    func detectActiveProjectPaths() -> Set<String> {
        Set(detectActiveAgentLocations().map { $0.cwd })
    }

    /// Collect `(providerId, cwd)` pairs for every running process whose
    /// `comm` matches a binary advertised by an enabled provider. Pids are
    /// grouped by provider so each `lsof` invocation only resolves cwds for
    /// the binaries owned by one provider, preserving attribution.
    func detectActiveAgentLocations() -> Set<ActiveAgentLocation> {
        let binariesByProvider = enabledProviderBinaries()
        guard !binariesByProvider.isEmpty else { return [] }

        let pidsByProvider = listAgentPidsByProvider(binariesByProvider: binariesByProvider)
        guard !pidsByProvider.isEmpty else { return [] }

        var result: Set<ActiveAgentLocation> = []
        for (providerId, pids) in pidsByProvider {
            for cwd in collectCwds(pids: pids) {
                result.insert(ActiveAgentLocation(providerId: providerId, cwd: cwd))
            }
        }
        return result
    }

    /// cwd hit on island.path → mark the island's most-recent session active.
    /// Path-only matching, kept for callers that don't yet thread provider
    /// attribution through. SessionScanner already sorts sessions by
    /// lastModified desc, so sessions[0] is newest.
    func applyStatuses(activeProjectPaths: Set<String>, to islands: inout [ProjectIsland]) {
        let normalized = Set(activeProjectPaths.map(Self.normalize))
        applyStatuses(islands: &islands) { island in
            normalized.contains(Self.normalize(island.path))
        }
    }

    /// Provider-scoped variant: an island is active only when a process
    /// owned by the same provider was found running in its cwd.
    func applyStatuses(activeLocations: Set<ActiveAgentLocation>, to islands: inout [ProjectIsland]) {
        let normalized = Set(activeLocations.map {
            ActiveAgentLocation(providerId: $0.providerId, cwd: Self.normalize($0.cwd))
        })
        applyStatuses(islands: &islands) { island in
            normalized.contains(ActiveAgentLocation(
                providerId: island.providerId,
                cwd: Self.normalize(island.path)
            ))
        }
    }

    // MARK: - Private

    /// Shared status-reduction loop. `isActive` decides whether an island has
    /// a live process; per-session status (.active/.recentlyIdle/.archived)
    /// follows the original rules.
    private func applyStatuses(
        islands: inout [ProjectIsland],
        isActive: (ProjectIsland) -> Bool
    ) {
        let now = Date()
        let recentThreshold: TimeInterval = 24 * 60 * 60

        for i in islands.indices {
            let islandActive = isActive(islands[i])
            for j in islands[i].sessions.indices {
                let session = islands[i].sessions[j]
                if islandActive && j == 0 {
                    islands[i].sessions[j].status = .active
                } else if now.timeIntervalSince(session.lastModified) < recentThreshold {
                    islands[i].sessions[j].status = .recentlyIdle
                } else {
                    islands[i].sessions[j].status = .archived
                }
            }
        }
    }

    /// Map each enabled provider's process binaries to its id, in registry
    /// order. The first provider to claim a binary wins (per the spec's
    /// "first match by registry order" rule for the unlikely case of
    /// duplicate binary names across providers).
    private func enabledProviderBinaries() -> [(binary: String, providerId: String)] {
        let providers = readEnabledProviders()
        var pairs: [(binary: String, providerId: String)] = []
        var seen: Set<String> = []
        for provider in providers {
            for binary in provider.processBinaryNames where !seen.contains(binary) {
                pairs.append((binary, provider.id))
                seen.insert(binary)
            }
        }
        return pairs
    }

    /// Hop to main if needed — `AgentProviderRegistry` is `@MainActor`. The
    /// hot caller `detectActiveAgentLocations()` already runs from main
    /// (via `CoveViewModel.refresh()`), so the sync hop is rare.
    private func readEnabledProviders() -> [any AgentProvider] {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { AgentProviderRegistry.shared.enabled() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { AgentProviderRegistry.shared.enabled() }
        }
    }

    /// Run `ps` once and bucket the resulting pids by providerId using the
    /// binary→provider lookup.
    private func listAgentPidsByProvider(
        binariesByProvider: [(binary: String, providerId: String)]
    ) -> [String: [Int32]] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("[ProcessDetector] ps failed: \(error)")
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return [:] }

        let lookup: [String: String] = Dictionary(
            binariesByProvider.map { ($0.binary, $0.providerId) },
            uniquingKeysWith: { first, _ in first }
        )

        var bucketed: [String: [Int32]] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, let pid = Int32(parts[0]) else { continue }

            // comm column may contain a path; take the basename and look up
            // exactly. Same matching rule TerminalDetector uses, so detection
            // is consistent across the two services.
            let commName = (parts[1..<parts.count].joined(separator: " ") as NSString).lastPathComponent
            if let providerId = lookup[commName] {
                bucketed[providerId, default: []].append(pid)
            }
        }
        return bucketed
    }

    /// One `lsof` call for all pids — `-F n` emits `n<path>` lines for cwd.
    private func collectCwds(pids: [Int32]) -> Set<String> {
        guard !pids.isEmpty else { return [] }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = [
            "-a", "-d", "cwd", "-F", "n",
            "-p", pids.map(String.init).joined(separator: ",")
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            print("[ProcessDetector] lsof failed: \(error)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var cwds: Set<String> = []
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n") {
                let path = String(line.dropFirst())
                if !path.isEmpty {
                    cwds.insert(path)
                }
            }
        }
        return cwds
    }

    private static func normalize(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        return p
    }
}
