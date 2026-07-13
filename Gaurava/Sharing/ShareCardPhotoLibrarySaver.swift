import Foundation
import Photos
import UniformTypeIdentifiers

enum ShareCardPhotoLibrarySaver {
    static func savePNGData(_ data: Data) async throws {
        let status = await addOnlyAuthorizationStatus()
        guard status == .authorized || status == .limited else {
            throw ShareCardPhotoSaveError.notAuthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.png.identifier

            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: options)
        }
    }

    private static func addOnlyAuthorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else {
            return current
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum ShareCardPhotoSaveError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            appLocalizedValue("Photos access was not granted.")
        }
    }
}
