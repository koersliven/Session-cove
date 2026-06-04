import Foundation

/// Singleton registry of installed `AgentProvider`s.
///
/// As of step 10, `enabled()` reads from
/// `CoveSettings.shared.enabledProviders` — that property is the single
/// source of truth for which providers are active. Unknown ids in the
/// setting are silently ignored (filtered through `compactMap`) so a
/// renamed-or-removed provider does not crash subsequent launches.
@MainActor
final class AgentProviderRegistry {
    static let shared = AgentProviderRegistry()

    private(set) var providers: [String: any AgentProvider] = [:]

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

    /// Provider associated with a given hook request, with a Claude fallback.
    ///
    /// Views (HookQuestionView, CompletionPingCard, …) call this instead of
    /// reaching into the dictionary directly so that:
    ///   * an unknown / stale `providerId` (e.g. a provider that was removed
    ///     while a pending file still mentions it) never produces a nil and
    ///     forces views to handle the optional;
    ///   * the default surface remains Claude — which is also the legacy
    ///     decode default for `HookPermissionRequest.providerId`.
    func provider(for request: HookPermissionRequest) -> any AgentProvider {
        providers[request.providerId] ?? ClaudeProvider()
    }

    /// Returns the subset of registered providers that are currently
    /// enabled per `CoveSettings.enabledProviders`. Unknown ids in the
    /// setting are dropped. Order is stable: providers are sorted by
    /// `id` so callers can rely on a deterministic ordering for UI
    /// lists.
    func enabled() -> [any AgentProvider] {
        let enabledIds = CoveSettings.shared.enabledProviders
        return enabledIds
            .compactMap { providers[$0] }
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
