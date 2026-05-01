import Foundation

public protocol LyricsProviding: Sendable {
    func fetchLyrics(for track: Track) async throws -> LyricsPayload?
}

public enum LyricsError: LocalizedError {
    case invalidResponse
    case httpError(status: Int, details: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "歌词服务返回了无效结果"
        case let .httpError(status, details):
            return "歌词服务请求失败 (\(status)): \(details)"
        }
    }
}

public final class LRCLibClient: LyricsProviding, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchLyrics(for track: Track) async throws -> LyricsPayload? {
        for query in candidateQueries(for: track) {
            guard let url = makeURL(query: query) else { continue }
            var request = URLRequest(url: url)
            request.setValue("NotchLyrics/0.1 (+macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LyricsError.invalidResponse
            }
            if http.statusCode == 404 {
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LyricsError.httpError(status: http.statusCode, details: Self.decodeErrorDetails(from: data))
            }

            let payload = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            if let synced = payload.syncedLyrics {
                let lines = parseLRC(synced)
                if !lines.isEmpty {
                    return LyricsPayload(sourceName: "LRCLIB", lines: lines, isSynced: true)
                }
            }

            if let plain = payload.plainLyrics {
                let lines = parsePlainLyrics(plain, durationMS: track.durationMS)
                if !lines.isEmpty {
                    return LyricsPayload(sourceName: "LRCLIB", lines: lines, isSynced: false)
                }
            }
        }
        return nil
    }

    private func makeURL(query: SearchQuery) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = query.queryItems
        return components?.url
    }

    private func candidateQueries(for track: Track) -> [SearchQuery] {
        let normalizedTitle = normalized(track.title)
        let compactTitle = compactTitleVariant(normalizedTitle)
        let primaryArtist = normalized(track.artists.first ?? track.artistLine)
        let artistLine = normalized(track.artistLine)
        let album = normalized(track.album)
        let duration = String(track.durationMS / 1000)

        return [
            SearchQuery(trackName: normalizedTitle, artistName: artistLine, albumName: album, duration: duration),
            SearchQuery(trackName: normalizedTitle, artistName: primaryArtist, albumName: album, duration: duration),
            SearchQuery(trackName: normalizedTitle, artistName: primaryArtist, albumName: nil, duration: duration),
            SearchQuery(trackName: compactTitle, artistName: primaryArtist, albumName: nil, duration: duration),
            SearchQuery(trackName: compactTitle, artistName: primaryArtist, albumName: nil, duration: nil)
        ].uniqued()
    }

    private func normalized(_ input: String) -> String {
        input
            .replacingOccurrences(of: #"\s*\[(.*?)\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\((Remaster(ed)?|Live|Deluxe.*?|Mono|Stereo).*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\((feat|ft|with)\..*?\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*-\s*(Remaster(ed)?|Live|Deluxe.*?|Mono|Stereo).*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*(feat|ft|with)\..*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactTitleVariant(_ input: String) -> String {
        input
            .replacingOccurrences(of: #"\s*/\s*.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseLRC(_ text: String) -> [LyricsLine] {
        var result: [LyricsLine] = []

        for rawLine in text.components(separatedBy: .newlines) {
            guard let close = rawLine.firstIndex(of: "]"), rawLine.hasPrefix("[") else { continue }
            let timestamp = String(rawLine[rawLine.index(after: rawLine.startIndex)..<close])
            let lyricText = String(rawLine[rawLine.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            guard let ms = Self.parseTimestamp(timestamp), !lyricText.isEmpty else { continue }
            result.append(LyricsLine(timestampMS: ms, text: lyricText))
        }

        return result.sorted { $0.timestampMS < $1.timestampMS }
    }

    private func parsePlainLyrics(_ text: String, durationMS: Int) -> [LyricsLine] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }
        let step = max(durationMS / max(lines.count, 1), 1500)
        return lines.enumerated().map { index, line in
            LyricsLine(timestampMS: index * step, text: line)
        }
    }

    private static func parseTimestamp(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]) else { return nil }
        let secParts = parts[1].split(separator: ".")
        guard let seconds = Int(secParts[0]) else { return nil }
        let fraction = secParts.count > 1 ? String(secParts[1]) : "0"
        let padded = String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        guard let ms = Int(padded) else { return nil }
        return minutes * 60_000 + seconds * 1_000 + ms
    }

    private static func decodeErrorDetails(from data: Data) -> String {
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            return text
        }
        return "服务拒绝了请求"
    }
}

private struct SearchQuery: Hashable {
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: String?

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName)
        ]
        if let albumName, !albumName.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: albumName))
        }
        if let duration, !duration.isEmpty {
            items.append(URLQueryItem(name: "duration", value: duration))
        }
        return items
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private struct LRCLibResponse: Decodable {
    let plainLyrics: String?
    let syncedLyrics: String?

    enum CodingKeys: String, CodingKey {
        case plainLyrics = "plainLyrics"
        case syncedLyrics = "syncedLyrics"
    }
}
