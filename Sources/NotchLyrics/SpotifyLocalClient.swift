import Foundation

public enum SpotifyLocalClientError: LocalizedError {
    case executionFailed(String)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case let .executionFailed(details):
            return "本地 Spotify 读取失败: \(details)"
        case let .invalidPayload(details):
            return "本地 Spotify 返回了无效数据: \(details)"
        }
    }
}

public struct LocalPlaybackState: Sendable {
    public let track: Track?
    public let sourceDescription: String

    public init(track: Track?, sourceDescription: String) {
        self.track = track
        self.sourceDescription = sourceDescription
    }
}

public final class SpotifyLocalClient: @unchecked Sendable {
    public enum PlaybackCommand: Sendable {
        case previousTrack
        case togglePlayPause
        case nextTrack

        fileprivate var appleScriptCommand: String {
            switch self {
            case .previousTrack:
                return "previous track"
            case .togglePlayPause:
                return "playpause"
            case .nextTrack:
                return "next track"
            }
        }
    }

    private let scriptRunner: @Sendable () throws -> String

    public init() {
        self.scriptRunner = SpotifyLocalClient.defaultScriptRunner
    }

    public init(scriptRunner: @escaping @Sendable () throws -> String) {
        self.scriptRunner = scriptRunner
    }

    public func currentTrack() async throws -> LocalPlaybackState {
        let output = try scriptRunner()
        return try Self.parse(output: output)
    }

    public func perform(_ command: PlaybackCommand) async throws {
        _ = try Self.runAppleScript([
            "if application \"Spotify\" is running then",
            "tell application \"Spotify\" to \(command.appleScriptCommand)",
            "else",
            "error \"Spotify is not running\"",
            "end if"
        ])
    }

    private static func defaultScriptRunner() throws -> String {
        try runAppleScript([
            "if application \"Spotify\" is running then",
            "tell application \"Spotify\"",
            "if player state is stopped then return \"STOPPED\"",
            "set t to current track",
            "set artworkURL to \"\"",
            "try",
            "set artworkURL to artwork url of t as text",
            "end try",
            "return (player state as text) & \"||\" & (name of t) & \"||\" & (artist of t) & \"||\" & (album of t) & \"||\" & (duration of t as text) & \"||\" & (player position as text) & \"||\" & artworkURL",
            "end tell",
            "else",
            "return \"NOT_RUNNING\"",
            "end if"
        ])
    }

    private static func runAppleScript(_ lines: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = lines.flatMap { ["-e", $0] }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw SpotifyLocalClientError.executionFailed(errorText.isEmpty ? "osascript exited with \(process.terminationStatus)" : errorText)
        }

        return output
    }

    public static func parse(output: String) throws -> LocalPlaybackState {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "NOT_RUNNING" {
            return LocalPlaybackState(track: nil, sourceDescription: "本地 Spotify 未运行")
        }
        if trimmed == "STOPPED" {
            return LocalPlaybackState(track: nil, sourceDescription: "本地 Spotify 当前没有播放内容")
        }

        let parts = trimmed.components(separatedBy: "||")
        guard parts.count >= 6 else {
            throw SpotifyLocalClientError.invalidPayload(trimmed)
        }

        let state = parts[0].lowercased()
        let title = parts[1]
        let artist = parts[2]
        let album = parts[3]
        let durationRaw = parts[4]
        let positionRaw = parts[5]
        let artworkRaw = parts.indices.contains(6) ? parts[6].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        if title.isEmpty {
            return LocalPlaybackState(track: nil, sourceDescription: "本地 Spotify 当前没有播放内容")
        }

        let durationMS = Int(Double(durationRaw) ?? 0)
        let progressMS = Int((Double(positionRaw) ?? 0) * 1000)
        let isPlaying = state == "playing"

        if artist.isEmpty, album.isEmpty, title.localizedCaseInsensitiveContains("ad-free") {
            return LocalPlaybackState(track: nil, sourceDescription: "本地 Spotify 当前播放的是广告")
        }

        let track = Track(
            id: "local:\(title)::\(artist)::\(album)",
            title: title,
            artists: artist.isEmpty ? [] : [artist],
            album: album,
            durationMS: max(durationMS, progressMS),
            progressMS: progressMS,
            isPlaying: isPlaying,
            artworkURL: artworkRaw.isEmpty ? nil : URL(string: artworkRaw)
        )

        return LocalPlaybackState(track: track, sourceDescription: "通过本地 Spotify 读取")
    }
}
