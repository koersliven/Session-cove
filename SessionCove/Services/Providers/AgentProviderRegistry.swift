import Foundation

/// Singleton registry of installed `AgentProvider`s.
///
/// Step 1 ships only `ClaudeProvider`; the registry's `enabled()` set is
/// hard-coded to `["claude"]`. A later step will replace that with a
/// user-controlled `CoveSettings.enabledProviders` list. Existing services
/// continue to use their hard-coded paths until they are migrated to look up
/// a provider here, so introducing the registry is a no-op at runtime.
@MainActor
final class AgentProviderRegistry {
    static let shared = AgentProviderRegistry()

    private(set) var providers: [String: any AgentProvider] = [:]

    /// Provider ids considered "enabled" for now. Step 10 replaces this
    /// hard-coded set with a user-facing setting.
    private let enabledIds: Set<String> = ["claude"]

    private init() {
        bootstrap()
    }

    /// Registers a provider, keyed by its `id`. Idempotent — re-registering
    /// the same id simply overwrites the previous value.
    func register(_ provider: any AgentProvider) {
        providers[provider.id] = provider
    }

    /// Looks up a provider by its stable id (e.g. `"claude"`).
    func provider(for id: String) -> (any AgentProvider)? {
        providers[id]
    }

    /// Returns the subset of registered providers that are currently
    /// enabled. Order is stable: providers are sorted by `id` so callers
    /// can rely on a deterministic ordering for UI lists.
    func enabled() -> [any AgentProvider] {
        providers.values
            .filter { enabledIds.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    /// Registers the built-in providers. Called once from `init` and safe to
    /// call again (registration is idempotent).
    ///
    /// Note: `QoderProvider`, `QoderWorkProvider`, and `CursorProvider` are
    /// registered here so that future UI (step 10) can list them as available
    /// choices, but they are intentionally absent from `enabledIds` above. As
    /// long as `enabled()` excludes them, scanners / watchers / hook
    /// installers never touch `~/.qoder/`, `~/.qoderwork/`, or `~/.cursor/`.
    private func bootstrap() {
        register(ClaudeProvider())
        register(QoderProvider())
        register(QoderWorkProvider())
        register(CursorProvider())
    }
}
