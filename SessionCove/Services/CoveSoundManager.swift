import AppKit
import Foundation
import SwiftUI

/// CoveSoundManager: 为 Session Cove 提供潜水员戴夫 (Dave the Diver) 风格的海洋音效管理
/// 使用 AppKit 的 NSSound 实现轻量级播放，适合菜单栏应用。
final class CoveSoundManager: @unchecked Sendable {
    static let shared = CoveSoundManager()
    
    private let defaults = UserDefaults.standard
    private let soundQueue = DispatchQueue(label: "cove.sound", qos: .userInteractive)
    private var soundCache: [CoveSoundEvent: NSSound] = [:]
    
    /// 音效事件定义
    enum CoveSoundEvent: String, CaseIterable, Sendable {
        case sonarPing     = "sonar_ping"     // 权限请求到达 (Sonar Alert)
        case waterSplash   = "water_splash"   // 视图展开/收起 (Dive/Surface)
        case bubblePop     = "bubble_pop"     // 按钮点击/操作完成 (UI Click)
        case oceanAmbient  = "ocean_ambient"  // App 启动 (Deep Sea Start)
        case treasureFound = "treasure_found" // 会话恢复成功 (Item Get)
        
        var fileName: String { rawValue }
    }
    
    private init() {
        // 预加载所有音效
        for event in CoveSoundEvent.allCases {
            if let sound = loadSound(event.fileName) {
                soundCache[event] = sound
            }
        }
    }
    
    /// 播放指定事件的音效
    /// - Parameters:
    ///   - event: 音效事件
    ///   - volumeOverride: 可选的音量覆盖 (0.0 - 1.0)，会与 settings.soundVolume 相乘
    func play(_ event: CoveSoundEvent, volumeOverride: Float? = nil) {
        // Read CoveSettings keys directly via UserDefaults (the source of truth)
        // — keys must match CoveSettings.Key (see Settings.swift) or settings will silently no-op.
        let enabledKey = "coveSoundEnabled"
        let volumeKey = "coveSoundVolume"
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        guard enabled else { return }

        let baseVolume: Float
        if defaults.object(forKey: volumeKey) != nil {
            baseVolume = Float(defaults.double(forKey: volumeKey))
        } else {
            baseVolume = 0.6
        }

        soundQueue.async { [self] in
            guard let sound = soundCache[event] else {
                if let newSound = loadSound(event.fileName) {
                    soundCache[event] = newSound
                    playSound(newSound, baseVolume: baseVolume, override: volumeOverride)
                }
                return
            }
            playSound(sound, baseVolume: baseVolume, override: volumeOverride)
        }
    }

    private func playSound(_ sound: NSSound, baseVolume: Float, override: Float?) {
        if sound.isPlaying {
            sound.stop()
        }
        let factor = override ?? 1.0
        sound.volume = max(0, min(1, baseVolume * factor))
        sound.play()
    }
    
    private func loadSound(_ name: String) -> NSSound? {
        let bundle = Bundle.module
        if let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") {
            return NSSound(contentsOf: url, byReference: false)
        }
        if let url = bundle.url(forResource: name, withExtension: "wav") {
            return NSSound(contentsOf: url, byReference: false)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") {
            return NSSound(contentsOf: url, byReference: false)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            return NSSound(contentsOf: url, byReference: false)
        }
        print("[CoveSoundManager] Warning: Sound not found: \(name).wav")
        return nil
    }
}

extension View {
    func playCoveSound(_ event: CoveSoundManager.CoveSoundEvent) {
        CoveSoundManager.shared.play(event)
    }
}
