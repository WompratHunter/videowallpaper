# Each bounded context is its own SwiftPM target

The POC compiled every file into one `swiftc` module with a Makefile, and the standards said "no SwiftPM, no Xcode project". We reversed that: the app is a SwiftPM package with one library target per context (Library, Rotation, Playback, Presence, Daylight, Desktop) plus `Application`, and a thin executable target. A context's domain code stays `internal`; only its ports, commands and events are `public`, so the compiler, not convention, keeps contexts from reaching into each other. SwiftPM is also the path to the Mac App Store, where signing and provisioning (and WeatherKit later) need an Xcode project, which will be a thin wrapper that depends on this package.

## Considered Options

- One `swiftc` module, boundaries by convention and lint: what we had; nothing stops a context from reaching into another's internals.
- Separate `swiftc -emit-module` libraries from the Makefile: enforces boundaries but means hand-maintaining build order, and it's fragile for App Store signing.
