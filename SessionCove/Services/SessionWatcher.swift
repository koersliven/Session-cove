import Foundation

final class SessionWatcher: Sendable {
    private let projectsPath: String
    private let onChange: @Sendable () -> Void
    private let stream: UnsafeSendableWrapper<FSEventStreamRef?>

    init(onChange: @escaping @Sendable () -> Void) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.projectsPath = "\(home)/.claude/projects"
        self.onChange = onChange
        self.stream = UnsafeSendableWrapper(nil)
    }

    func start() {
        let pathsToWatch = [projectsPath] as CFArray

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
