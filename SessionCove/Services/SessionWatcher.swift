import Foundation

final class SessionWatcher: Sendable {
    private let roots: [String]
    private let onChange: @Sendable () -> Void
    private let stream: UnsafeSendableWrapper<FSEventStreamRef?>

    /// Backward-compatible initializer used before multi-provider support.
    /// Watches the Claude transcript root only, mirroring legacy behavior.
    convenience init(onChange: @escaping @Sendable () -> Void) {
        let claudeRoot = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        self.init(roots: [claudeRoot], onChange: onChange)
    }

    /// Multi-root initializer. One FSEventStream watches the union of
    /// `roots`; any change in any root coalesces into a single `onChange`
    /// callback. Non-existent roots are tolerated by FSEvents (it watches
    /// them lazily once they appear).
    init(roots: [URL], onChange: @escaping @Sendable () -> Void) {
        self.roots = roots.map(\.path)
        self.onChange = onChange
        self.stream = UnsafeSendableWrapper(nil)
    }

    func start() {
        guard !roots.isEmpty else { return }
        let pathsToWatch = roots as CFArray

        var context = FSEventStreamContext()

        let callback: @convention(c) (
            ConstFSEventStreamRef, UnsafeMutableRawPointer?,
            Int, UnsafeMutableRawPointer,
            UnsafePointer<FSEventStreamEventFlags>,
            UnsafePointer<FSEventStreamEventId>
        ) -> Void = { _, clientCallBackInfo, _, _, _, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<SessionWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }

        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let eventStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        stream.value = eventStream
        FSEventStreamSetDispatchQueue(eventStream, DispatchQueue.main)
        FSEventStreamStart(eventStream)
    }

    func stop() {
        guard let eventStream = stream.value else { return }
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        stream.value = nil
    }
}

final class UnsafeSendableWrapper<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
