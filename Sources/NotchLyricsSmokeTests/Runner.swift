import Foundation
import NotchLyricsCore

@main
struct NotchLyricsSmokeTestsRunner {
    static func main() async {
        do {
            try await testSpotifyFallback()
            try await testSpotifyFallbackID()
            try await testSpotifyAdResponse()
            try await testLRCSyncedFallback()
            try await testLRCPlainLyrics()
            try testSpotifyLocalParsing()
            try testSpotifyLocalArtworkParsing()
            try testSpotifyLocalStopped()
            print("Smoke tests passed: 8/8")
            Foundation.exit(EXIT_SUCCESS)
        } catch {
            fputs("Smoke tests failed: \(error)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func testSpotifyFallback() async throws {
        let session = makeMockSession()
        let recorder = LockedStrings()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw SmokeTestError.failed("Spotify fallback test missing request URL")
            }
            recorder.append(url.path)

            if url.path == "/v1/me/player" {
                let data = #"{"error":{"status":502,"message":"bad gateway"}}"#.data(using: .utf8)!
                return (makeHTTPResponse(url: url, statusCode: 502), data)
            }

            let data = #"""
            {
              "is_playing": true,
              "progress_ms": 42000,
              "currently_playing_type": "track",
              "item": {
                "id": "track-123",
                "name": "Song A",
                "duration_ms": 180000,
                "album": {
                  "name": "Album A",
                  "images": [{ "url": "https://example.com/a.jpg" }]
                },
                "artists": [{ "name": "Artist A" }]
              }
            }
            """#.data(using: .utf8)!
            return (makeHTTPResponse(url: url, statusCode: 200), data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = SpotifyClient(session: session) { "token-123" }
        let track = try await client.currentTrack()
        let paths = recorder.snapshot()

        try expect(paths == ["/v1/me/player", "/v1/me/player/currently-playing"], "Spotify fallback path sequence was wrong: \(paths)")
        try expect(track?.id == "track-123", "Spotify fallback did not parse track id")
        try expect(track?.title == "Song A", "Spotify fallback did not parse title")
        try expect(track?.artistLine == "Artist A", "Spotify fallback did not parse artist")
    }

    @MainActor
    private static func testSpotifyFallbackID() async throws {
        let session = makeMockSession()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw SmokeTestError.failed("Spotify fallback id test missing request URL")
            }
            let data = #"""
            {
              "is_playing": false,
              "progress_ms": 1000,
              "currently_playing_type": "track",
              "item": {
                "name": "Untitled",
                "duration_ms": 200000,
                "album": {
                  "name": "Album B",
                  "images": []
                },
                "artists": [{ "name": "Artist B" }, { "name": "Artist C" }]
              }
            }
            """#.data(using: .utf8)!
            return (makeHTTPResponse(url: url, statusCode: 200), data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = SpotifyClient(session: session) { "token-123" }
        let track = try await client.currentTrack()

        try expect(track?.id == "spotify:Untitled::Album B::Artist B,Artist C", "Spotify fallback id was not generated correctly")
        try expect(track?.isPlaying == false, "Spotify playback state should be paused")
    }

    @MainActor
    private static func testSpotifyAdResponse() async throws {
        let session = makeMockSession()

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw SmokeTestError.failed("Spotify ad test missing request URL")
            }
            let data = #"""
            {
              "is_playing": true,
              "progress_ms": 3000,
              "currently_playing_type": "ad",
              "item": null
            }
            """#.data(using: .utf8)!
            return (makeHTTPResponse(url: url, statusCode: 200), data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = SpotifyClient(session: session) { "token-123" }
        let track = try await client.currentTrack()

        try expect(track == nil, "Spotify ad response should return nil track")
    }

    private static func testLRCSyncedFallback() async throws {
        let session = makeMockSession()
        let recorder = LockedStrings()
        let track = Track(
            id: "1",
            title: "My Song (Live)",
            artists: ["Main Artist", "Guest Artist"],
            album: "Album Name",
            durationMS: 210000,
            progressMS: 0,
            isPlaying: true,
            artworkURL: nil
        )

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw SmokeTestError.failed("LRCLib synced fallback test missing request URL")
            }
            recorder.append(url.query ?? "")

            if recorder.count() == 1 {
                return (makeHTTPResponse(url: url, statusCode: 404), Data())
            }

            let data = #"""
            {
              "syncedLyrics": "[00:01.50]first line\n[00:03.00]second line",
              "plainLyrics": null
            }
            """#.data(using: .utf8)!
            return (makeHTTPResponse(url: url, statusCode: 200), data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = LRCLibClient(session: session)
        let lyrics = try await client.fetchLyrics(for: track)
        let queries = recorder.snapshot()

        try expect(queries.count == 2, "LRCLib should try two queries before succeeding")
        try expect(queries[0].contains("artist_name=Main%20Artist,%20Guest%20Artist"), "LRCLib first query should use full artist line")
        try expect(queries[1].contains("artist_name=Main%20Artist"), "LRCLib second query should fall back to primary artist")
        try expect(lyrics?.isSynced == true, "LRCLib should mark synced lyrics correctly")
        try expect(lyrics?.lines.map(\.timestampMS) == [1500, 3000], "LRCLib synced timestamps were parsed incorrectly")
    }

    private static func testLRCPlainLyrics() async throws {
        let session = makeMockSession()
        let track = Track(
            id: "2",
            title: "Plain Song",
            artists: ["Artist"],
            album: "Album",
            durationMS: 9000,
            progressMS: 0,
            isPlaying: true,
            artworkURL: nil
        )

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw SmokeTestError.failed("LRCLib plain lyrics test missing request URL")
            }
            let data = #"""
            {
              "syncedLyrics": null,
              "plainLyrics": "line one\nline two\nline three"
            }
            """#.data(using: .utf8)!
            return (makeHTTPResponse(url: url, statusCode: 200), data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let client = LRCLibClient(session: session)
        let lyrics = try await client.fetchLyrics(for: track)

        try expect(lyrics?.isSynced == false, "Plain lyrics should not be marked synced")
        try expect(lyrics?.lines.map(\.timestampMS) == [0, 3000, 6000], "Plain lyrics timeline was generated incorrectly")
        try expect(lyrics?.lines.last?.text == "line three", "Plain lyrics text order was generated incorrectly")
    }

    private static func testSpotifyLocalParsing() throws {
        let state = try SpotifyLocalClient.parse(output: "playing||Song, A||Artist, B||Album C||24946||2.286999940872")
        try expect(state.track?.title == "Song, A", "Local Spotify title parsing failed")
        try expect(state.track?.artistLine == "Artist, B", "Local Spotify artist parsing failed")
        try expect(state.track?.progressMS == 2286, "Local Spotify progress parsing failed")
        try expect(state.track?.durationMS == 24946, "Local Spotify duration parsing failed")
        try expect(state.track?.isPlaying == true, "Local Spotify playing state parsing failed")
    }

    private static func testSpotifyLocalArtworkParsing() throws {
        let state = try SpotifyLocalClient.parse(output: "playing||Song||Artist||Album||24946||2.2||https://example.com/cover.jpg")
        try expect(state.track?.artworkURL?.absoluteString == "https://example.com/cover.jpg", "Local Spotify artwork URL parsing failed")
    }

    private static func testSpotifyLocalStopped() throws {
        let state = try SpotifyLocalClient.parse(output: "STOPPED")
        try expect(state.track == nil, "Stopped local Spotify should not return a track")
    }
}
