import SwiftUI
import PhotosUI
import UIKit

extension PhotosPickerItem {
    /// Loads a photo as an upload-ready JPEG: downscaled (egress-friendly) and
    /// re-encoded, so HEIC / large iCloud photos become small JPEGs. Retries once
    /// because `loadTransferable(type: Data.self)` can transiently return nil for
    /// an iCloud photo that still needs to download. Returns nil only if the
    /// photo truly can't be read.
    func loadUploadJPEG(maxDimension: CGFloat = 2000, quality: CGFloat = 0.8) async -> Data? {
        for attempt in 0..<2 {
            if let data = try? await loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = image.downscaledJPEG(maxDimension: maxDimension, quality: quality) {
                return jpeg
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        return nil
    }
}

extension UIImage {
    /// Re-encodes to JPEG, first shrinking so the longest side is ≤ maxDimension
    /// (in pixels). Keeps uploads and egress small; converts HEIC/PNG to JPEG.
    func downscaledJPEG(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return jpegData(compressionQuality: quality) }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // newSize is already in pixels — don't multiply by screen scale
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
