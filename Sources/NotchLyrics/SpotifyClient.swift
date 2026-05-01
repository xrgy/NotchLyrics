import Foundation

public enum SpotifyClientError: LocalizedError {
    case invalidPayload
    case httpError(status: Int, details: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Spotify 返回了无效数据"
        case let .httpError(status, details):
            if status == 403, details.localizedCaseInsensitiveContains("Active premium subscription required for the owner of the app") {
                return "Spotify 拒绝了播放状态接口：当前 Client ID 对应的开发者应用所有者账号需要有效的 Premium 订阅。"
            }
            return "Spotify 播放状态请求失败 (\(status)): \(details)"
        }
    }
}

@MainActor
public final class SpotifyClient {
    private let session: URLSession
    private let accessTokenProvider: @Sendable () async throws -> String

    init(authManager: SpotifyAuthManager, session: URLSession = .shared) {
        self.accessTokenProvider = { try await authManager.validAccessToken() }
        self.session = session
    }

    public init(
        session: URLSession = .shared,
        accessTokenProvider: @escaping @Sendable () async throws -> String
    ) {
        self.session = session
        self.accessTokenProvider = accessTokenProvider
    }

    public func currentTrack() async throws -> Track? {
        do {
            return try await fetchTrack(from: "https://api.spotify.com/v1/me/player")
        } catch let error as SpotifyClientError {
            switch error {
            case .invalidPayload, .httpError(status: 404, _), .httpError(status: 502, _), .httpError(status: 503, _):
                return try await fetchTrack(from: "https://api.spotify.com/v1/me/player/currently-playing")
            default:
                throw error
            }
        }
    }

    private func fetchTrack(from endpoint: String) async throws -> Track? {
        let accessToken = try await accessTokenProvider()
        var request = URLRequest(url: URL(string: endpoint)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NotchLyrics/0.1 (+macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyClientError.invalidPayload
        }

        if http.statusCode == 204 {
            return nil
        }

        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyClientError.httpError(status: http.statusCode, details: Self.decodeErrorDetails(from: data))
        }

        let dto = try JSONDecoder().decode(PlaybackStateResponse.self, from: data)
        guard dto.currentlyPlayingType != "ad" else { return nil }
        guard let item = dto.item else { return nil }

        let fallbackID = [
            item.name,
            item.album.name,
            item.artists.map(\.name).joined(separator: ",")
        ]
        .joined(separator: "::")

        return Track(
            id: item.id ?? "spotify:\(fallbackID)",
            title: item.name,
            artists: item.artists.map(\.name),
            album: item.album.name,
            durationMS: item.durationMS,
            progressMS: dto.progressMS ?? 0,
            isPlaying: dto.isPlaying,
            artworkURL: item.album.images.first?.url
        )
    }

    private static func decodeErrorDetails(from data: Data) -> String {
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"]
        {
            if let object = error as? [String: Any] {
                let status = object["status"].map { "\($0)" }
                let message = object["message"] as? String
                let reason = object["reason"] as? String
                return [status, message, reason].compactMap { $0 }.joined(separator: " - ")
            }

            if let text = error as? String {
                let description = json["error_description"] as? String
                return [text, description].compactMap { $0 }.joined(separator: " - ")
            }
        }

        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        return "未知错误"
    }
}

private struct PlaybackStateResponse: Decodable {
    let isPlaying: Bool
    let progressMS: Int?
    let currentlyPlayingType: String?
    let item: Item?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMS = "progress_ms"
        case currentlyPlayingType = "currently_playing_type"
        case item
    }

    struct Item: Decodable {
        let id: String?
        let name: String
        let durationMS: Int
        let album: Album
        let artists: [Artist]

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case durationMS = "duration_ms"
            case album
            case artists
        }
    }

    struct Album: Decodable {
        let name: String
        let images: [Image]
    }

    struct Artist: Decodable {
        let name: String
    }

    struct Image: Decodable {
        let url: URL
    }
}
