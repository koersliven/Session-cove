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

    /// Load a user-supplied custom pet image from an absolute file path.
    /// Returns nil when the path is empty/missing or the file can't be
    /// decoded as an image (caller falls back to the built-in sprites).
    /// Same alpha-crop treatment as bundled sprites so PNGs with transparent
    /// margins sit tight; fully opaque photos crop to their full frame
    /// (no-op) and render as-is.
    static func loadCustom(path: String?) -> NSImage? {
        guard let path, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return loadCropped(fromURL: URL(fileURLWithPath: path))
    }

    private static func loadCropped(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return loadCropped(fromURL: url)
    }

    private static func loadCropped(fromURL url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        // Crop to the alpha bounding box when the image has transparency.
        // For opaque images every pixel is above the alpha threshold, so the
        // bbox is the full frame and the result is identical to the source.
        if let bbox = alphaBoundingBox(in: cgImage),
           let cropped = cgImage.cropping(to: bbox) {
            return NSImage(cgImage: cropped, size: NSSize(width: bbox.width, height: bbox.height))
        }
        return image
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
