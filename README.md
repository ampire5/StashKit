# StashKit

Shared Swift package for macOS apps (FrameScrub, Loupe) that talk to a [Stash](https://stashapp.cc) media server
(developed against v0.31.1).

Requirements: macOS 26+, swift-tools 6.2 (the targets build in the Swift 5 language mode). The `StashKit` target links
the system NetFS framework (for `ShareMounter`); SwiftPM adds it for you.

![Stash's WebUI inside Loupe](https://raw.githubusercontent.com/ampire5/Loupe/main/docs/images/stash.webp)

## Products

- `StashKit`: the GraphQL client (`StashClient`), scene details for display (`StashSceneDetails`,
  `StashClient.sceneDetails(id:)`), the Stash-to-local path map (`StashPathMap`), play-activity bookkeeping
  (`StashActivity`, `StashActivityRequest`), the queue step gate (`QueueStepGate`) and the SMB share mounter
  (`ShareMounter.mount(_:timeout:completion:)`, through NetFS: the keychain password or the system sign-in dialog).
  - `StashPathMap(mounts:rules:rememberedDriveServer:)` turns the Windows paths Stash stores (`S:\Videos\…`,
    `\\server\share\…`) into local paths: `resolve(_:)` gives `.local(URL)`, `.needsMount(smbURL)` (hand it to
    `ShareMounter`) or `.unmapped`. Drive letters go to the `S$`-style admin shares of the server most of them are
    mounted from; UNC paths go to the same share on the same server (`.local` and case ignored).
  - `SMBMount.current()` lists the SMB shares mounted right now (server, share, mount point), the `mounts` input.
  - `StashPathRule` is an explicit prefix rule that wins over the share logic (the longest matching prefix, case
    ignored); `StashPathRule.parse(_:)` reads `stashPrefix=localPrefix` pairs separated by `;`.
- `StashKitUI`: `StashLibraryView`, the Stash WebUI in a web view, made once and kept so going back finds the same
  page; browser keys and buttons (⌘[ ⌘] ⌘R, back/forward, swipe; `goBack()` / `goForward()` for buttons the app reads
  itself), a load failure shown in place, `onPageLoaded` after each page load. It changes the page only through the
  `StashInterceptor`s the app gives it (a script injected at document start plus a handler for its bridge messages).
  `StashInterceptor.scenePlayer` puts the scene's cover and ▶ in place of Stash's player and hands the scene to the
  app (`StashScene`: id, file paths, resume point, whether it came from a list), and keeps Stash's queue so `step(_:)`
  can go to the next or previous scene. Its full form is `scenePlayer(onOpen:onBridgeMissing:)`: `onBridgeMissing`
  runs when the page has no `PluginApi` (not a Stash page, or a Stash without the plugin API), so the app can say so.

## Galleries (Loupe)

- `StashClient.gallery(id:)` and `findGalleries(variables:page:perPage:)` give `StashGallery` (id, title, the folder
  or zip file path as Stash wrote it); `firstGalleryPath()` is for a settings check.
- `StashInterceptor.galleryOpener(interceptsNewTabClicks:onOpen:)` takes a plain left click on a gallery in any list
  (Grid, List, Wall) and hands the app a `StashGalleryPick`: the gallery's id and, when the page's last
  `FindGalleries` answer holds it, that request's variables and the gallery's index in the whole list.
  `interceptsNewTabClicks` (default `false`) also takes ⌘-click and middle click (`pick.newTab`) and ⇧-click
  (`pick.newWindow`); with `false` those clicks stay Stash's own. The script wraps `window.fetch` to see the
  request, so a list's search, sort and criteria come along as the page sent them.
- `StashGalleryList` steps through that list page by page (skipping galleries without a path; `.end` at its ends).
- `StashLibraryView.navigate(to:)` moves the page to a path without a reload (a virtual gallery's own page).

## Usage

```swift
import AppKit
import StashKit
import StashKitUI

let stashURL = URL(string: "http://stash.local:9999")!
let client = StashClient(baseURL: stashURL, apiKey: nil)
let map = StashPathMap(mounts: SMBMount.current(), rules: StashPathRule.parse(#"S:\Clips=/Volumes/Clips"#))

let library = StashLibraryView(url: stashURL, interceptors: [
    .scenePlayer(onOpen: { scene in
        guard let path = scene.paths.first else { return }
        switch map.resolve(path) {
        case .local(let file): print("play", file.path, "from", scene.resumeTime)
        case .needsMount(let share): ShareMounter.mount(share) { result in print("mounted:", result) }
        case .unmapped: print("no local path for", path)
        }
    }, onBridgeMissing: { print("not a Stash page with the plugin API") }),
    .galleryOpener(interceptsNewTabClicks: true) { pick in
        print("gallery", pick.id, pick.newTab ? "in a new tab" : "here")
    },
])
library.onPageLoaded = { print("page loaded") }
// later: let details = try await client.sceneDetails(id: scene.id)
```

## Tests

```sh
swift test
```

The scene fixture in `Tests/StashKitTests/Fixtures/find-scene.json` has the shape of a live `findScene` answer with
invented content.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ampire5/StashKit.git", from: "0.1.0"),
],
// in your target:
dependencies: [.product(name: "StashKit", package: "StashKit"), .product(name: "StashKitUI", package: "StashKit")]
```

Used by [Loupe](https://github.com/ampire5/Loupe) and [FrameScrub](https://github.com/ampire5/FrameScrub).

## Issues and contributions

Bug reports and pull requests are welcome at [github.com/ampire5/StashKit/issues](https://github.com/ampire5/StashKit/issues).
Please run `swift test` before sending a change.

## License

MIT — see [LICENSE](LICENSE).
