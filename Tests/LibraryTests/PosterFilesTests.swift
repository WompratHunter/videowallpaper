import Foundation
@testable import Library
import Testing

// MARK: - Poster file tests: names, pruning and the launch underlay

@Suite struct PosterFilesTests {
    @Test func posterNamesAreStablePerVersion() {
        let file = VideoFile(size: 1_000, modified: Date(timeIntervalSince1970: 1_700_000_000))
        let name = posterFileName(forVideoAt: "/v/rain.mp4", file: file)
        #expect(name == posterFileName(forVideoAt: "/v/rain.mp4", file: file))
        #expect(isPosterFileName(name), "a generated name is recognised as a Poster: \(name)")
        #expect(name.hasSuffix(".jpg") && !name.hasPrefix("."), "Poster names are visible JPEGs: \(name)")
        // Golden value: the name must not change between runs (Swift's Hasher is seeded per process).
        #expect(name == "poster-2a375343f308636b.jpg")
        #expect(name != posterFileName(forVideoAt: "/v/sea.mp4", file: file), "another path gets another Poster")
        #expect(
            name != posterFileName(forVideoAt: "/v/rain.mp4", file: VideoFile(size: 1_001, modified: file.modified)),
            "a replaced file (new size) gets a new Poster")
        #expect(
            name != posterFileName(
                forVideoAt: "/v/rain.mp4",
                file: VideoFile(size: 1_000, modified: file.modified.addingTimeInterval(1))),
            "a touched file (new mtime) gets a new Poster")
        #expect(!isPosterFileName(".poster.jpg"), "the legacy Poster is not one of the new names")
        #expect(!isPosterFileName("notes.txt"), "other files are not Posters")
    }

    @Test func stalePostersArePrunedButTheCurrentOneIsKept() {
        let keep = "poster-0000000000000001.jpg"
        let gone = "poster-0000000000000002.jpg"
        let current = "poster-0000000000000003.jpg"
        #expect(
            stalePosters(in: [keep, gone, current, ".DS_Store", "readme.txt"], keeping: [keep], current: current)
                == [gone])
        #expect(stalePosters(in: [keep], keeping: [keep], current: current).isEmpty)
        #expect(stalePosters(in: [], keeping: [keep], current: current).isEmpty)
        // An unreadable Wallpaper folder lists no videos; the Current Poster (the desktop picture) must still survive.
        #expect(stalePosters(in: [gone, current], keeping: [], current: current) == [gone])
    }

    @Test func theLaunchUnderlayIsNeverBlack() {
        let playing = "poster-000000000000000a.jpg"
        let newer = "poster-000000000000000b.jpg"
        let older = "poster-000000000000000c.jpg"
        let previousVersion = "poster-00000000000000ff.jpg"
        // The video to play has its Poster: it comes first, then the others', then the desktop picture.
        #expect(
            underlayCandidates(toPlay: playing, waiting: [newer, older], saved: [older, playing, newer])
                == [.poster(playing), .poster(newer), .poster(older), .desktopPicture])
        // First launch after install: nothing analysed, no Posters yet. The desktop picture shows, not black.
        #expect(underlayCandidates(toPlay: nil, waiting: [newer, older], saved: []) == [.desktopPicture])
        // Nothing analysed yet, but a waiting video has a saved Poster: it shows (a still can't flash).
        #expect(
            underlayCandidates(toPlay: nil, waiting: [newer, older], saved: [older, ".DS_Store"])
                == [.poster(older), .desktopPicture])
        // Upgrade: only Posters named by an earlier version remain; they are a last resort after the desktop picture.
        #expect(
            underlayCandidates(toPlay: nil, waiting: [newer], saved: [previousVersion])
                == [.desktopPicture, .poster(previousVersion)])
        // The video to play listed again among the waiting ones is tried once.
        #expect(
            underlayCandidates(toPlay: newer, waiting: [newer], saved: [newer]) == [.poster(newer), .desktopPicture])
        // An empty folder still has the desktop picture.
        #expect(underlayCandidates(toPlay: nil, waiting: [], saved: []) == [.desktopPicture])
    }
}
