import Foundation

public enum MediaFileDiscovery {
    public static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "ts", "m2ts",
        "m4a", "mp3", "flac", "ogg", "opus", "wav", "aiff", "aif", "caf"
    ]

    public static func playableFiles(in directory: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { url in
            guard supportedExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { return false }
            return FileManager.default.isReadableFile(atPath: url.path)
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
