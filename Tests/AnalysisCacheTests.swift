import Foundation

// MARK: - Analysis cache tests: lookup, encode/decode, prune, eligibility, Analysis order

func runAnalysisCacheTests() {
    runCacheLookupTests()
    runCacheCodingTests()
    runCachePruneTests()
    runEligibleVideoTests()
    runAnalysisOrderTests()
}

private let rainFile = VideoFile(size: 1_000, modified: Date(timeIntervalSince1970: 1_700_000_000))
private let rain = Analysis(meanLuminance: 0.16, flashesPerSecond: 1, posterSeconds: 7.5, poster: "poster-1.jpg")
private let strobe = Analysis(meanLuminance: 0.5, flashesPerSecond: 6, posterSeconds: 0, poster: "poster-2.jpg")

private func runCacheLookupTests() {
    var cache = AnalysisCache()
    checkEqual(cache.analysis(forVideoAt: "/v/rain.mp4", file: rainFile), nil)
    cache.store(rain, forVideoAt: "/v/rain.mp4", file: rainFile)
    checkEqual(cache.analysis(forVideoAt: "/v/rain.mp4", file: rainFile), rain)
    checkEqual(cache.analysis(forVideoAt: "/v/other.mp4", file: rainFile), nil)
    // A replaced or touched file is analysed again.
    let replaced = VideoFile(size: 1_001, modified: rainFile.modified)
    checkEqual(cache.analysis(forVideoAt: "/v/rain.mp4", file: replaced), nil)
    let touched = VideoFile(size: 1_000, modified: rainFile.modified.addingTimeInterval(1))
    checkEqual(cache.analysis(forVideoAt: "/v/rain.mp4", file: touched), nil)
    // Sub-millisecond differences (a date's round trip through the file system) still match.
    let sameMillisecond = VideoFile(size: 1_000, modified: rainFile.modified.addingTimeInterval(0.000_1))
    checkEqual(cache.analysis(forVideoAt: "/v/rain.mp4", file: sameMillisecond), rain)
}

private func runCacheCodingTests() {
    var cache = AnalysisCache()
    cache.store(rain, forVideoAt: "/v/rain.mp4", file: rainFile)
    cache.store(strobe, forVideoAt: "/v/strobe.mp4", file: rainFile)
    let data = try? cache.json()
    let decoded = data.flatMap(AnalysisCache.init(json:))
    checkEqual(decoded, cache)
    checkEqual(decoded?.analysis(forVideoAt: "/v/strobe.mp4", file: rainFile), strobe)
    checkEqual(AnalysisCache(json: Data("not json".utf8)), nil)
    checkEqual(AnalysisCache(json: Data(#"{"version": 99, "videos": {}}"#.utf8)), nil)
    checkEqual(AnalysisCache(json: Data(#"{"version": 1, "videos": {}}"#.utf8)), AnalysisCache())
}

private func runCachePruneTests() {
    var cache = AnalysisCache()
    cache.store(rain, forVideoAt: "/v/rain.mp4", file: rainFile)
    cache.store(strobe, forVideoAt: "/v/strobe.mp4", file: rainFile)
    var unchanged = cache
    check(!unchanged.prune(present: ["/v/rain.mp4": rainFile, "/v/strobe.mp4": rainFile]), "nothing to prune")
    checkEqual(unchanged, cache)
    // Deleted and replaced videos lose their entries; new videos don't add any.
    let replaced = VideoFile(size: 2_000, modified: rainFile.modified)
    check(cache.prune(present: ["/v/rain.mp4": rainFile, "/v/strobe.mp4": replaced, "/v/new.mp4": rainFile]),
          "a replaced video is pruned")
    checkEqual(cache.analysis(forVideoAt: "/v/rain.mp4", file: rainFile), rain)
    checkEqual(cache.analysis(forVideoAt: "/v/strobe.mp4", file: rainFile), nil)
    check(cache.prune(present: [:]), "a deleted video is pruned")
    checkEqual(cache, AnalysisCache())
}

private func runEligibleVideoTests() {
    let older = Date(timeIntervalSince1970: 1_000)
    let newer = Date(timeIntervalSince1970: 2_000)
    let settled = ["rain.mp4": older, "strobe.mp4": newer, "pending.mp4": newer]
    let analyses = ["rain.mp4": rain, "strobe.mp4": strobe]
    checkEqual(
        screenEligible(settled: settled, analyses: analyses, overrides: []),
        [EligibleVideo(name: "rain.mp4", modified: older, meanLuminance: 0.16)])
    checkEqual(
        screenEligible(settled: settled, analyses: analyses, overrides: ["strobe.mp4"]).map(\.name),
        ["rain.mp4", "strobe.mp4"])
    // An analysis for a video no longer settled is ignored.
    checkEqual(screenEligible(settled: ["pending.mp4": newer], analyses: analyses, overrides: []), [])
}

private func runAnalysisOrderTests() {
    let settled = [
        "a.mp4": Date(timeIntervalSince1970: 1_000),
        "b.mp4": Date(timeIntervalSince1970: 3_000),
        "c.mp4": Date(timeIntervalSince1970: 2_000),
        "d.mp4": Date(timeIntervalSince1970: 3_000)
    ]
    checkEqual(videosToAnalyse(settled: settled, analysed: ["c.mp4"]), ["d.mp4", "b.mp4", "a.mp4"])
    checkEqual(videosToAnalyse(settled: settled, analysed: Set(settled.keys)), [])
}
