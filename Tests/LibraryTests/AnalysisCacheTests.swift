import Foundation
@testable import Library
import SharedKernel
import Testing

// MARK: - Analysis cache tests: lookup, encode/decode, prune, eligibility, Analysis order

private let rainFile = VideoFile(size: 1_000, modified: Date(timeIntervalSince1970: 1_700_000_000))
private let rain = Analysis(meanLuminance: 0.16, flashesPerSecond: 1, posterSeconds: 7.5, poster: "poster-1.jpg")
private let strobe = Analysis(meanLuminance: 0.5, flashesPerSecond: 6, posterSeconds: 0, poster: "poster-2.jpg")

@Suite struct AnalysisCacheTests {
    @Test func anAnalysisIsFoundOnlyForTheSameVersion() {
        var cache = AnalysisCache()
        #expect(cache.analysis(forVideoAt: "/v/rain.mp4", file: rainFile) == nil)
        cache.store(rain, forVideoAt: "/v/rain.mp4", file: rainFile)
        #expect(cache.analysis(forVideoAt: "/v/rain.mp4", file: rainFile) == rain)
        #expect(cache.analysis(forVideoAt: "/v/other.mp4", file: rainFile) == nil)
        // A replaced or touched file is analysed again.
        let replaced = VideoFile(size: 1_001, modified: rainFile.modified)
        #expect(cache.analysis(forVideoAt: "/v/rain.mp4", file: replaced) == nil)
        let touched = VideoFile(size: 1_000, modified: rainFile.modified.addingTimeInterval(1))
        #expect(cache.analysis(forVideoAt: "/v/rain.mp4", file: touched) == nil)
        // Sub-millisecond differences (a date's round trip through the file system) still match.
        let sameMillisecond = VideoFile(size: 1_000, modified: rainFile.modified.addingTimeInterval(0.000_1))
        #expect(cache.analysis(forVideoAt: "/v/rain.mp4", file: sameMillisecond) == rain)
    }

    @Test func theCacheRoundTripsThroughJSON() {
        var cache = AnalysisCache()
        cache.store(rain, forVideoAt: "/v/rain.mp4", file: rainFile)
        cache.store(strobe, forVideoAt: "/v/strobe.mp4", file: rainFile)
        let data = try? cache.json()
        let decoded = data.flatMap(AnalysisCache.init(json:))
        #expect(decoded == cache)
        #expect(decoded?.analysis(forVideoAt: "/v/strobe.mp4", file: rainFile) == strobe)
        #expect(AnalysisCache(json: Data("not json".utf8)) == nil)
        #expect(AnalysisCache(json: Data(#"{"version": 99, "videos": {}}"#.utf8)) == nil)
        #expect(AnalysisCache(json: Data(#"{"version": 1, "videos": {}}"#.utf8)) == AnalysisCache())
    }

    @Test func pruningDropsDeletedAndReplacedVideos() {
        var cache = AnalysisCache()
        cache.store(rain, forVideoAt: "/v/rain.mp4", file: rainFile)
        cache.store(strobe, forVideoAt: "/v/strobe.mp4", file: rainFile)
        var unchanged = cache
        let prunedUnchanged = unchanged.prune(present: ["/v/rain.mp4": rainFile, "/v/strobe.mp4": rainFile])
        #expect(!prunedUnchanged, "nothing to prune")
        #expect(unchanged == cache)
        // Deleted and replaced videos lose their entries; new videos don't add any.
        let replaced = VideoFile(size: 2_000, modified: rainFile.modified)
        let prunedReplaced = cache.prune(
            present: ["/v/rain.mp4": rainFile, "/v/strobe.mp4": replaced, "/v/new.mp4": rainFile])
        #expect(prunedReplaced, "a replaced video is pruned")
        #expect(cache.analysis(forVideoAt: "/v/rain.mp4", file: rainFile) == rain)
        #expect(cache.analysis(forVideoAt: "/v/strobe.mp4", file: rainFile) == nil)
        let prunedDeleted = cache.prune(present: [:])
        #expect(prunedDeleted, "a deleted video is pruned")
        #expect(cache == AnalysisCache())
    }

    @Test func onlyScreenedVideosAreEligible() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let settled = ["rain.mp4": older, "strobe.mp4": newer, "pending.mp4": newer]
        let file = { (modified: Date) in VideoFile(size: 1_000, modified: modified) }
        let files = settled.mapValues(file)
        let analyses = ["rain.mp4": rain, "strobe.mp4": strobe]
        #expect(
            screenEligible(settled: files, analyses: analyses, overrides: []) == [
                EligibleVideo(
                    id: VideoID("rain.mp4"), version: Version(size: 1_000, modified: older), meanLuminance: 0.16)
            ])
        #expect(
            screenEligible(settled: files, analyses: analyses, overrides: ["strobe.mp4"]).map(\.name)
                == ["rain.mp4", "strobe.mp4"])
        // An analysis for a video no longer settled is ignored.
        #expect(screenEligible(settled: ["pending.mp4": file(newer)], analyses: analyses, overrides: []).isEmpty)
        // Stand-ins at launch: the unanalysed video counts (its Poster is a still), the Excluded one doesn't.
        #expect(
            notExcludedNewestFirst(settled: settled, analyses: analyses, overrides: []) == ["pending.mp4", "rain.mp4"])
        #expect(
            notExcludedNewestFirst(settled: settled, analyses: analyses, overrides: ["strobe.mp4"])
                == ["strobe.mp4", "pending.mp4", "rain.mp4"])
        #expect(notExcludedNewestFirst(settled: [:], analyses: analyses, overrides: []).isEmpty)
    }

    @Test func theNewestVideosAreAnalysedFirst() {
        let settled = [
            "a.mp4": Date(timeIntervalSince1970: 1_000),
            "b.mp4": Date(timeIntervalSince1970: 3_000),
            "c.mp4": Date(timeIntervalSince1970: 2_000),
            "d.mp4": Date(timeIntervalSince1970: 3_000)
        ]
        #expect(videosToAnalyse(settled: settled, analysed: ["c.mp4"]) == ["d.mp4", "b.mp4", "a.mp4"])
        #expect(videosToAnalyse(settled: settled, analysed: Set(settled.keys)).isEmpty)
    }
}
