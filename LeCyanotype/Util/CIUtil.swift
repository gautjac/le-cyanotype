import CoreImage
import Metal
import OSLog

/// Shared Core Image plumbing. One GPU-backed context for the whole app — building a
/// CIContext is expensive, so the render engine, the live preview, the planche-contact
/// grid, and the exporter all share this one.
enum CIUtil {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()

    static let context: CIContext = {
        if let device {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false,
                                                          .name: "LeCyanotype"])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    /// Downscale `image` so its longest side is at most `maxDimension`, for a snappy
    /// live preview. Returns the image untouched if already small enough.
    static func downscale(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let e = image.extent
        let longest = max(e.width, e.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// Centralised loggers. Quiet by default; the render subsystem carries its own
/// category so the kernel-load / graceful-degradation path is traceable.
enum Log {
    static let render = Logger(subsystem: "com.jac.LeCyanotype", category: "render")
    static let photo = Logger(subsystem: "com.jac.LeCyanotype", category: "photo")
    static let export = Logger(subsystem: "com.jac.LeCyanotype", category: "export")
    static let store = Logger(subsystem: "com.jac.LeCyanotype", category: "store")
}
