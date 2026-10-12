import Foundation
@testable import Library
import SharedKernel
import Testing

// MARK: - Catalogue tests
// Every Video in the folder with why it does or doesn't play.

private let file = VideoFile(size: 1_000, modified: Date(timeIntervalSince1970: 1_700_000_000))

private func analysis(flashes: Double) -> Analysis {
    Analysis(meanLuminance: 0.2, flashesPerSecond: flashes, posterSeconds: 1, poster: "poster-1.jpg")
}

@Test func eachVideoHasItsCatalogueStatus() {
    let present = [
        "copying.mp4": file, "queued.mp4": file, "broken.mp4": file, "strobe.mp4": file, "kept.mp4": file,
        "rain.mp4": file
    ]
    let entries = catalogue(
        present: present, settled: Set(present.keys).subtracting(["copying.mp4"]),
        analyses: [
            "strobe.mp4": analysis(flashes: 6), "kept.mp4": analysis(flashes: 5), "rain.mp4": analysis(flashes: 1)
        ],
        failed: ["broken.mp4"], overrides: ["kept.mp4"])
    #expect(entries.map(\.id.fileName) == present.keys.sorted())
    #expect(Dictionary(uniqueKeysWithValues: entries.map { ($0.id.fileName, $0.status) }) == [
        "copying.mp4": .settling, "queued.mp4": .analysing, "broken.mp4": .analysisFailed,
        "strobe.mp4": .excluded(flashesPerSecond: 6), "kept.mp4": .overridden(flashesPerSecond: 5),
        "rain.mp4": .eligible
    ])
    #expect(entries.allSatisfy { $0.version == file.version })
    #expect(entries.filter(\.status.isPlayable).map(\.id.fileName) == ["kept.mp4", "rain.mp4"])
}

@Test func anAnalysisOutranksAnOlderFailureAndSettlingComesFirst() {
    let present = ["rain.mp4": file]
    // Not settled: settling, whatever is known of it.
    #expect(catalogue(
        present: present, settled: [], analyses: ["rain.mp4": analysis(flashes: 1)], failed: ["rain.mp4"],
        overrides: []).map(\.status) == [.settling])
    #expect(catalogue(
        present: present, settled: ["rain.mp4"], analyses: ["rain.mp4": analysis(flashes: 1)], failed: ["rain.mp4"],
        overrides: []).map(\.status) == [.eligible])
}
