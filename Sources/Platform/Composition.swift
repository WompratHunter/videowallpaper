import Application

// MARK: - Composition
// The only place every concrete adapter is named: each context's adapters are built in `Composition+<Context>.swift`
// with the paths and ports they use, and handed to the coordinator as that context's service.

@MainActor
enum Composition {
    static func coordinator(clock: ClockPort) -> Coordinator {
        Coordinator(
            library: library(), rotation: rotation(), playback: playback(), presence: presence(),
            daylight: daylight(), desktop: desktop(), clock: clock, settings: UserDefaultsSettings())
    }
}
