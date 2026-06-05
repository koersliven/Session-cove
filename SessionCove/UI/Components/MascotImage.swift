import AppKit

enum MascotImage {
    // Defaults — Claude prefix for back-compat. Existing call sites that
    // don't yet thread a provider id through (status item, notch head,
    // CoveMascotView) keep working unchanged. Multi-provider call sites
    // can call `loadMascot(state:prefix:)` below to vary the asset by
    // provider while still falling back to Claude art.
    static let working: NSImage? = loadCropped("claude_working")
    static let sleeping: NSImage? = loadCropped("claude_sleeping")
    static let attention: NSImage? = loadCropped("claude_attention")
    static let idle: NSImage? = loadCropped("claude_idle")
    static let wink: NSImage? = loadCropped("claude_wink")
    static let island: NSImage? = loadCropped("island")
    /// Pet-mode micro-action sprites. White-bg art for now; transparent
    /// versions can replace these without code changes.
    static let petBlink: NSImage? = loadCropped("claude_pet_blink")
    static let petSip: NSImage? = loadCropped("claude_pet_sip")
    static let petBubble: NSImage? = loadCropped("claude_pet_bubble")
    static let petCelebrate: NSImage? = loadCropped("claude_pet_celebrate")

    /// Resolves a per-provider mascot by trying `<prefix>_<state>` first and
    /// falling back to `claude_<state>` when the provider has no dedicated
    /// asset (the situation today for Qoder / QoderWork / Cursor — they all
    /// reuse the Claude art). `loadCropped` returns nil silently when an
    /// asset is missing, so the fallback chain never crashes.
    static func loadMascot(state: PixelMascotState, prefix: String) -> NSImage? {
        let suffix: String
        switch state {
        case .working: suffix = "working"
        case .idle: suffix = "idle"
        case .sleeping: suffix = "sleeping"
        case .attention: suffix = "attention"
        case .dragged: suffix = "wink"
        case .petBlink: suffix = "pet_blink"
        case .petSip: suffix = "pet_sip"
        case .petBubble: suffix = "pet_bubble"
        case .petCelebrate: suffix = "pet_celebrate"
        }
        // Provider fallback chain (non-Claude only):
        //   1. `<prefix>_<state>` — full per-state art (none today for
        //      Qoder/Cursor — placeholder for future variants).
        //   2. `<prefix>_mascot`  — single-image mascot used as the
        //      character for every base state. Loses pet-blink/sip
        //      animation but keeps the IDENTITY consistent (Qoder
        //      drawing for a Qoder session, Cursor for Cursor).
        //   3. `claude_<state>`   — final fallback, ensures we never
        //      render a blank.
        if prefix != "claude" {
            if let perState = loadCropped("\(prefix)_\(suffix)") {
                return perState
            }
            if let single = loadCropped("\(prefix)_mascot") {
                return single
            }
        }
        return loadCropped("claude_\(suffix)")
    }

    private static func loadCropped(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bbox = alphaBoundingBox(in: cgImage),
              let cropped = cgImage.cropping(to: bbox) else {
            return nil
        }

        return NSImage(cgImage: cropped, size: NSSize(width: bbox.width, height: bbox.height))
    }

    private static func alphaBoundingBox(in image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundPixel = false

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                if alpha > 8 {
                    foundPixel = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard foundPixel else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
