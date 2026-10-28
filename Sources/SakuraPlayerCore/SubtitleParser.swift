import Foundation

public struct SubtitleCue: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }

    public func contains(_ time: TimeInterval) -> Bool { time >= start && time < end }
}

public enum SubtitleParserError: LocalizedError, Equatable {
    case unreadableFile
    case unsupportedFormat
    case invalidContent

    public var errorDescription: String? {
        switch self {
        case .unreadableFile: return "The subtitle file could not be read."
        case .unsupportedFormat: return "This subtitle format is not supported yet."
        case .invalidContent: return "The subtitle file contains no readable cues."
        }
    }
}

public enum SubtitleParser {
    public static func parse(url: URL) throws -> [SubtitleCue] {
        let supported = Set(["srt", "vtt", "ass", "ssa"])
        guard supported.contains(url.pathExtension.lowercased()) else { throw SubtitleParserError.unsupportedFormat }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw SubtitleParserError.unreadableFile
        }
        let cues = parse(text: text)
        guard !cues.isEmpty else { throw SubtitleParserError.invalidContent }
        return cues
    }

    public static func parse(text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.split(separator: "\n").contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("dialogue:")
        }) {
            return parseASS(text: normalized)
        }
        return parseTimedText(text: normalized)
    }

    private static func parseTimedText(text: String) -> [SubtitleCue] {
        let lines = text.components(separatedBy: "\n")
        var cues: [SubtitleCue] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.uppercased() == "WEBVTT" || line.hasPrefix("NOTE") {
                index += 1
                continue
            }

            let timingLine: String
            if line.contains("-->") {
                timingLine = line
            } else if index + 1 < lines.count, lines[index + 1].contains("-->") {
                index += 1
                timingLine = lines[index]
            } else {
                index += 1
                continue
            }

            let parts = timingLine.components(separatedBy: "-->")
            guard parts.count >= 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1].split(separator: " ", maxSplits: 1).first.map(String.init) ?? "") else {
                index += 1
                continue
            }
            index += 1
            var textLines: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textLines.append(lines[index].trimmingCharacters(in: .whitespaces))
                index += 1
            }
            let cueText = textLines.joined(separator: "\n")
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            if end > start, !cueText.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: cueText)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// Parses timed dialogue from ASS/SSA while intentionally dropping style
    /// overrides that the SwiftUI subtitle overlay cannot render faithfully.
    private static func parseASS(text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.lowercased().hasPrefix("dialogue:") else { continue }
            let payload = line.dropFirst("Dialogue:".count).trimmingCharacters(in: .whitespaces)
            let fields = payload.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 10,
                  let start = parseTimestamp(fields[1]),
                  let end = parseTimestamp(fields[2]),
                  end > start else { continue }

            let cueText = cleanASSCueText(fields[9])
            guard !cueText.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: cueText))
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func cleanASSCueText(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: #"\N"#, with: "\n")
            .replacingOccurrences(of: #"\n"#, with: "\n")
            .replacingOccurrences(of: #"\h"#, with: " ")

        while let start = cleaned.firstIndex(of: "{"),
              let end = cleaned[start...].firstIndex(of: "}") {
            cleaned.removeSubrange(start...end)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTimestamp(_ value: String) -> TimeInterval? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count), let seconds = Double(parts.last ?? "") else { return nil }
        let minuteIndex = parts.count - 2
        guard let minutes = Double(parts[minuteIndex]) else { return nil }
        let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
        return hours * 3600 + minutes * 60 + seconds
    }
}
