// The real thumbnail decoder, via ImageIO.

import AppKit
import ImageIO
import UttrflowClipboard

extension PanelThumbnailSource {
    /// Decoded only after the stored picture's header fits the capture budget.
    static let system = PanelThumbnailSource { file, maxPixel in
        Self.load(file, maxPixel: maxPixel) { source, options in
            CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        }
    }

    /// Reads a bounded thumbnail from a stored image, returning nil for an unreadable or oversized header.
    static func load(
        _ file: URL, maxPixel: Int, decode: (CGImageSource, CFDictionary) -> CGImage?
    ) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0,
            ClipboardBudget.standard.fitsPicture(width: width, height: height)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge(
                width: width, height: height, covering: maxPixel),
        ]
        guard let image = decode(source, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// The same from the picture's size; a panorama is capped at four times `edge`, since the row crops it anyway.
    static func longestEdge(width: Int, height: Int, covering edge: Int) -> Int {
        let shorter = min(width, height)
        let longer = max(width, height)
        guard shorter > 0, shorter > edge else { return max(edge, min(longer, edge * 4)) }
        let scaled = (longer * edge + shorter - 1) / shorter
        return min(scaled, edge * 4)
    }
}
