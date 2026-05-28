import AppKit

enum MascotImage {
    static let working: NSImage? = loadCropped("claude_working")
    static let sleeping: NSImage? = loadCropped("claude_sleeping")
    static let attention: NSImage? = loadCropped("claude_attention")
    static let idle: NSImage? = loadCropped("claude_idle")
    static let island: NSImage? = loadCropped("island")

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
