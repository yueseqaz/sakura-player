import Foundation

public enum SubtitleDiscovery {
    private static let supportedExtensions: Set<String> = ["srt", "vtt", "ass", "ssa"]

    public static func subtitles(for videoURL: URL) -> [URL] {
        let directory = videoURL.deletingLastPathComponent()
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { candidate in
            supportedExtensions.contains(candidate.pathExtension.lowercased()) && candidate.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(baseName) == .orderedSame
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
