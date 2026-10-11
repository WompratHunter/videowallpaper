import Application

// MARK: - Composition
// The only place every concrete adapter is named: each context's adapters are built in `Composition+<Context>.swift`
// with the paths and ports they use, and handed to the coordinator as that context's service. One argument per line,
// so a ticket that hands its context another port (the clock, settings) edits only its own line.

@MainActor
enum Composition {
    static func coordinator(clock: ClockPort) -> Coordinator {
        Coordinator(
            library: library(),
            rotation: rotation(),
            playback: playback(),
            presence: presence(),
            daylight: daylight(),
            desktop: desktop(),
            clock: clock,
            settings: UserDefaultsSettings())
    }
}
