import SwiftUI
import UIKit

struct ShareCardRenderedAsset {
    let image: UIImage
    let pngData: Data
    let fileURL: URL
}

enum ShareCardRenderer {
    @MainActor
    static func render(dashboard: DashboardSnapshot, configuration: ShareCardConfiguration) throws -> ShareCardRenderedAsset {
        let snapshot = ShareCardSnapshot(dashboard: dashboard)
        guard snapshot.hasWeightData else {
            throw ShareCardRenderError.noWeightData
        }

        let canvas = configuration.template.canvas
        let content = ShareJourneyCardView(snapshot: snapshot, configuration: configuration)
            .frame(width: canvas.points.width, height: canvas.points.height)
            .environment(\.colorScheme, configuration.colorScheme.swiftUIColorScheme)
            .dynamicTypeSize(.medium)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: canvas.points.width, height: canvas.points.height)
        renderer.scale = canvas.scale
        renderer.isOpaque = true
        renderer.colorMode = .nonLinear

        guard let image = renderer.uiImage, let cgImage = image.cgImage else {
            throw ShareCardRenderError.renderFailed
        }

        let expectedWidth = Int(canvas.pixels.width)
        let expectedHeight = Int(canvas.pixels.height)
        guard cgImage.width == expectedWidth, cgImage.height == expectedHeight else {
            throw ShareCardRenderError.unexpectedSize(
                actual: CGSize(width: cgImage.width, height: cgImage.height),
                expected: canvas.pixels
            )
        }

        guard let pngData = image.pngData() else {
            throw ShareCardRenderError.pngEncodingFailed
        }

        let fileURL = ShareExportFilename.temporaryFileURL(
            baseName: appLocalizedValue("Gaurava-Journey"),
            fileExtension: "png"
        )
        try pngData.write(to: fileURL, options: .atomic)

        return ShareCardRenderedAsset(image: image, pngData: pngData, fileURL: fileURL)
    }
}

enum ShareExportFilename {
    static func temporaryFileURL(baseName: String, fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeComponent(baseName))-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    private static func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let collapsed = mapped
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "Gaurava-Export" : collapsed
    }
}

enum ShareCardRenderError: LocalizedError {
    case noWeightData
    case renderFailed
    case pngEncodingFailed
    case unexpectedSize(actual: CGSize, expected: CGSize)

    var errorDescription: String? {
        switch self {
        case .noWeightData:
            appLocalizedValue("Add at least one weight entry before sharing a journey card.")
        case .renderFailed:
            appLocalizedValue("The journey card could not be rendered.")
        case .pngEncodingFailed:
            appLocalizedValue("The journey card could not be prepared as a PNG.")
        case let .unexpectedSize(actual, expected):
            // Developer-facing invariant violation that should never surface in normal
            // use; intentionally NOT localized so a debug precondition is not extracted
            // into the String Catalog and translated into hi/ta/te.
            "The journey card rendered at \(Int(actual.width))x\(Int(actual.height)), expected \(Int(expected.width))x\(Int(expected.height))."
        }
    }
}
