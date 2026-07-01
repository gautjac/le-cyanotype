import CoreImage
import UIKit
import Photos

/// Renders the finished tirage at full resolution and saves it to the photo library.
/// Uses the shared CIContext to bake the CIImage into a CGImage, then writes a JPEG
/// to Photos via PHPhotoLibrary.
enum ImageExporter {
    enum ExportError: Error { case renderFailed, notAuthorised }

    /// Render `image` to a high-quality JPEG `Data` (sRGB), suitable for saving or sharing.
    static func jpeg(from image: CIImage, quality: CGFloat = 0.95) -> Data? {
        let e = image.extent
        guard e.width > 0, e.height > 0, e.width.isFinite, e.height.isFinite else { return nil }
        guard let cg = CIUtil.context.createCGImage(
            image, from: e, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }

    /// A `UIImage` for on-screen display / sharing.
    static func uiImage(from image: CIImage) -> UIImage? {
        let e = image.extent
        guard e.width > 0, e.height > 0, e.width.isFinite, e.height.isFinite else { return nil }
        guard let cg = CIUtil.context.createCGImage(image, from: e) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Save the finished tirage to the user's photo library, requesting add-only
    /// authorization first.
    static func saveToPhotos(_ image: CIImage) async throws {
        guard let data = jpeg(from: image) else { throw ExportError.renderFailed }
        let status = await requestAddAuthorization()
        guard status == .authorized || status == .limited else { throw ExportError.notAuthorised }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
        Log.export.info("saved tirage to Photos")
    }

    private static func requestAddAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        return current
    }
}
