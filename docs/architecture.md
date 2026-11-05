# StashKit architecture

Current map; update when the client, bridge or path-resolution contract changes. The library provides server
integration; the host decides how a returned media item is opened, played or remembered.

## Targets and responsibilities

| Target | Role | Entry points |
|---|---|---|
| StashKit | GraphQL, returned data, path mapping, gallery navigation, activity and share mounting | `Sources/StashKit/StashClient.swift`, `Sources/StashKit/StashPathMap.swift`, `Sources/StashKit/ShareMounter.swift` |
| StashKitUI | Retained WebKit library and injectable interceptors | `Sources/StashKitUI/StashLibraryView.swift`, `Sources/StashKitUI/StashInterceptor.swift` |

The UI target depends on StashKit. The core target links NetFS for share mounting; there are no other package
dependencies. See `StashSceneDetails.swift`, `StashGallery.swift`, `StashActivity.swift` in `Sources/StashKit` for
returned values/activity rules. Source scripts live alongside their Swift bridge definitions.

## Ownership and flow

The host retains `StashLibraryView` across navigation so returning does not rebuild/reload the page. It supplies
interceptors and handles open callbacks. A page bridge message describes an item; the host resolves its paths with
`StashPathMap`, optionally mounts a share, then opens it through the app's existing media pipeline.
`StashPathMap` is mapping policy, not a media reader. Server identifiers/paths and local URLs remain distinct.
`StashClient` performs async network requests; the host supplies server configuration and credentials.
`StashGalleryList` is an actor that caches page tasks for navigation in one server result list. `QueueStepGate`
controls stepping coordination; it does not own a player.

WebKit operations and host UI callbacks belong to the UI thread. Share mounting runs outside UI work and returns
on the main actor. Its one-shot completion state is main-actor owned so NetFS and timeout callbacks share the
same completion gate. WebKit delegate completion handlers carry the SDK's main-actor isolation. The host must
guard obsolete opens/results when selection or configuration changes. Neither
bridge data nor a server path is an instruction to modify the application's configuration.

## Persistence and checks

The host owns credentials, configured path rules, resume state and settings persistence. This package supplies
request/value types and view session state; do not add app-global configuration as hidden library state.

Run `swift test --jobs 4`. `Tests/StashKitTests` includes synthetic GraphQL fixtures and path/bridge checks. Use
invented server data and generic paths in fixtures. Inspect the bridge script together with the corresponding
Swift message handler when changing either side; media opening belongs to Loupe/FrameScrub integration tests.
See [public usage](../README.md).
