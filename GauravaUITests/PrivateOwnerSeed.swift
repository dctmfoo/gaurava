import Foundation

enum PrivateOwnerSeed {
    static var path: String {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["GAURAVA_PRIVATE_OWNER_SEED_PATH"],
            repoLocalSeedPath
        ].compactMap { $0 }

        return candidates.first { fileManager.fileExists(atPath: $0) } ?? repoLocalSeedPath
    }

    private static var repoLocalSeedPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scratch/seed/gaurava/owner-seed.json")
            .path
    }
}
