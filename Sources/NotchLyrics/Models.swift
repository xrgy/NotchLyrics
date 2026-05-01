import Foundation

public struct Track: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String
    public let durationMS: Int
    public let progressMS: Int
    public let isPlaying: Bool
    public let artworkURL: URL?

    public init(
        id: String,
        title: String,
        artists: [String],
        album: String,
        durationMS: Int,
        progressMS: Int,
        isPlaying: Bool,
        artworkURL: URL?
    ) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.durationMS = durationMS
        self.progressMS = progressMS
        self.isPlaying = isPlaying
        self.artworkURL = artworkURL
    }

    public var artistLine: String {
        artists.joined(separator: ", ")
    }
}

public struct LyricsLine: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let timestampMS: Int
    public let text: String

    public init(timestampMS: Int, text: String) {
        self.timestampMS = timestampMS
        self.text = text
    }
}

public struct LyricsPayload: Equatable, Sendable {
    public let sourceName: String
    public let lines: [LyricsLine]
    public let isSynced: Bool

    public init(sourceName: String, lines: [LyricsLine], isSynced: Bool) {
        self.sourceName = sourceName
        self.lines = lines
        self.isSynced = isSynced
    }
}
