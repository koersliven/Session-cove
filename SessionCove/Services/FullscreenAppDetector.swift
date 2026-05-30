import AppKit

/// Detects whether the frontmost application is in fullscreen mode and notifies
/// subscribers when that state changes. PR 5 uses this to hide the notch panel
/// while a fullscreen app is active.
@MainActor
final class FullscreenAppDetector {
    static let shared = FullscreenAppDetector()

    /// 当前活跃 app 是否处于 fullscreen
    private(set) var isFullscreen: Bool = false

    private var observers: [NSObjectProtocol] = []
    private var subscribers: [UUID: (Bool) -> Void] = [:]

    private init() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(
            nc.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.recheck() }
            }
        )
        observers.append(
            nc.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.recheck() }
            }
        )
        recheck()
    }

    /// 订阅；返回 token 用于退订。回调首次推送当前状态。
    func subscribe(_ handler: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        handler(isFullscreen)
        return id
    }

    func unsubscribe(_ token: UUID) {
        subscribers.removeValue(forKey: token)
    }

    /// 检测当前 frontmost app 是否在 fullscreen space。
    /// 用 CGWindowListCopyWindowInfo 看顶层 window 是否覆盖整屏 + 没有菜单栏。
    private func recheck() {
        let newValue = Self.detectFullscreen()
        guard newValue != isFullscreen else { return }
        isFullscreen = newValue
        for (_, handler) in subscribers {
            handler(newValue)
        }
    }

    private static func detectFullscreen() -> Bool {
        // 1. 获取 frontmost app PID
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = frontApp.processIdentifier
        // 2. 取主屏 frame
        guard let mainScreen = NSScreen.main else { return false }
        let screenFrame = mainScreen.frame
        // 3. 列举 on-screen window，找 frontApp 拥有的 layer 0 window
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        for window in windows {
            guard let windowPID = window[kCGWindowOwnerPID as String] as? pid_t, windowPID == pid else { continue }
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
               let x = boundsDict["X"], let y = boundsDict["Y"],
               let w = boundsDict["Width"], let h = boundsDict["Height"] {
                let bounds = CGRect(x: x, y: y, width: w, height: h)
                // fullscreen 判据：window 覆盖整屏宽 + 高度 ≥ screen.frame 高（含菜单栏区域）
                if abs(bounds.width - screenFrame.width) < 2,
                   abs(bounds.height - screenFrame.height) < 2 {
                    return true
                }
            }
        }
        return false
    }

    deinit {
        // NSWorkspace observers 注销在任何线程都安全
        let nc = NSWorkspace.shared.notificationCenter
        for o in observers {
            nc.removeObserver(o)
        }
    }
}
