import Testing
import Foundation
@testable import BoxtubeCore

@Suite("Movies")
struct MovieTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func movie(_ id: String = "dQw4w9WgXcQ") -> Video {
        Video(id: id, channelId: "c", channelTitle: "YouTube Movies", title: "A Film", publishedAt: now, durationSeconds: 6600)
    }

    @Test func linksGiveTheVideoId() {
        let id = "dQw4w9WgXcQ"
        #expect(YouTubeLink.videoId(from: "https://www.youtube.com/watch?v=\(id)&t=10") == id)
        #expect(YouTubeLink.videoId(from: "https://youtu.be/\(id)?si=abc") == id)
        #expect(YouTubeLink.videoId(from: "https://m.youtube.com/watch?feature=share&v=\(id)") == id)
        #expect(YouTubeLink.videoId(from: "  \(id) ") == id)
        #expect(YouTubeLink.videoId(from: "https://www.youtube.com/embed/\(id)") == id)
        #expect(YouTubeLink.videoId(from: "not a link") == nil)
    }

    @Test func rentalsCountDownToStartThenToFinish() {
        let rented = now
        #expect(Rental.state(rentedAt: rented, startedAt: nil, now: now.addingTimeInterval(86_400)) == .notStarted(left: 29 * 86_400))
        #expect(Rental.label(.notStarted(left: 29 * 86_400)) == "29 days to start")
        let started = now.addingTimeInterval(5 * 86_400)
        #expect(Rental.state(rentedAt: rented, startedAt: started, now: started.addingTimeInterval(30 * 3600)) == .watching(left: 18 * 3600))
        #expect(Rental.label(.watching(left: 18 * 3600)) == "18 h left")
        #expect(Rental.state(rentedAt: rented, startedAt: started, now: started.addingTimeInterval(49 * 3600)) == .expired)
        #expect(Rental.state(rentedAt: rented, startedAt: nil, now: now.addingTimeInterval(31 * 86_400)) == .expired)
    }

    @Test func filingAndRefilingAMovie() async throws {
        let store = try Store.inMemory()
        try await store.addMovie(movie(), kind: .rented, now: now)
        try await store.setMovieStarted("dQw4w9WgXcQ", true, now: now.addingTimeInterval(3600))
        var rows = try await store.read { db in try Q.movies(db) }
        #expect(rows.count == 1)
        #expect(rows[0].movie.rentedAt == now)
        #expect(rows[0].movie.startedAt == now.addingTimeInterval(3600))

        try await store.setMovieKind("dQw4w9WgXcQ", .bought, now: now)
        rows = try await store.read { db in try Q.movies(db) }
        #expect(rows[0].movie.kind == .bought)
        #expect(rows[0].movie.rentedAt == nil && rows[0].movie.startedAt == nil)

        try await store.removeMovie("dQw4w9WgXcQ")
        #expect(try await store.read { db in try Q.movies(db) }.isEmpty)
    }

    @Test func moviesStayOutOfRecommendations() async throws {
        let store = try Store.inMemory()
        try await store.subscribe(Channel(id: "c", title: "YouTube Movies"))
        try await store.upsert(videos: [Video(id: "keepkeepkee", channelId: "c", channelTitle: "C", title: "A video", publishedAt: .now)])
        try await store.addMovie(Video(id: "dQw4w9WgXcQ", channelId: "c", channelTitle: "C", title: "A Film", publishedAt: .now), kind: .saved)
        let ids = try await store.read { db in try Q.recommendations(db, now: .now).map(\.id) }
        #expect(ids == ["keepkeepkee"])
    }
}
