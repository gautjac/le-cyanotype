import SwiftUI
import PhotosUI
import UIKit

/// A `PHPickerViewController` wrapper that hands back a correctly-oriented `CIImage`.
/// No depth or auxiliary data needed — Le Cyanotype works on any photograph.
struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: (CIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else { parent.dismiss(); return }
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { parent.dismiss(); return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage,
                   let ci = CIImage(image: image) {
                    let oriented = ci.oriented(forExifOrientation: Self.exif(image.imageOrientation))
                    DispatchQueue.main.async {
                        self.parent.onPick(oriented)
                        self.parent.dismiss()
                    }
                } else {
                    DispatchQueue.main.async { self.parent.dismiss() }
                }
            }
        }

        static func exif(_ o: UIImage.Orientation) -> Int32 {
            switch o {
            case .up: return 1
            case .down: return 3
            case .left: return 8
            case .right: return 6
            case .upMirrored: return 2
            case .downMirrored: return 4
            case .leftMirrored: return 5
            case .rightMirrored: return 7
            @unknown default: return 1
            }
        }
    }
}
