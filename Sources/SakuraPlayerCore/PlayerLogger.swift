import Foundation
import OSLog

public enum PlayerLogger {
    private static let logger = Logger(subsystem: "com.yueseqaz.SakuraPlayer", category: "playback")

    public static func loading(url: URL) {
        logger.info("Loading media \(url.lastPathComponent, privacy: .private(mask: .hash))")
    }

    public static func failure(_ error: Error) {
        logger.error("Playback failure (\(String(describing: type(of: error)), privacy: .public))")
    }
}
