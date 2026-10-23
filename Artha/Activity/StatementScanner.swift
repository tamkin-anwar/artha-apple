import ImageIO
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import VisionKit
#endif

/// Scanning a paper statement with the document camera (the one Notes and
/// Files use: finds the page's edges, flattens it, many pages in a row).
/// The pages become one PDF in memory, never saved to Photos or Files, and
/// go through the same review as any statement; the server reads a scan
/// with AI since it has no text (finance.routes._read_scanned_statement).
#if os(iOS)
struct StatementScanner: UIViewControllerRepresentable {
    /// The scanned pages as a PDF, or nil if the person cancelled.
    let onFinish: (Data?) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<min(scan.pageCount, StatementScanner.maxPages)).map { scan.imageOfPage(at: $0) }
            onFinish(StatementScanner.pdf(from: pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(nil)
        }
    }

    /// The server reads at most this many pages of a scan.
    static let maxPages = 12

    /// Each page drawn onto its own US Letter page, scaled to fit, as JPEG
    /// so the upload stays small.
    static func pdf(from pages: [UIImage]) -> Data? {
        guard !pages.isEmpty else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for page in pages {
                context.beginPage()
                let image = StatementPhoto.downscaled(page)
                let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
                image.draw(in: CGRect(origin: origin, size: size))
            }
        }
    }
}
#else
/// The document camera is an iPhone and iPad thing; a Mac imports files.
enum StatementScanner {
    static var isAvailable: Bool { false }
}
#endif

/// A photo of a statement, ready to send: upright, a JPEG whatever the
/// camera saved it as (HEIC), and no bigger than it needs to be to read.
enum StatementPhoto {
    static let longEdge: CGFloat = 2400

    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    #if os(iOS)
    static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longEdge / 2 else { return image }
        let scale = (longEdge / 2) / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    #endif
}
