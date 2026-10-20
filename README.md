# StashKit

Shared Swift package for macOS apps (FrameScrub, Loupe) that talk to a [Stash](https://stashapp.cc) media server
(developed against v0.31.1). macOS 26, Swift 6.2 tools, Swift 5 language mode.

## Products

- `StashKit`: the GraphQL client (`StashClient`), scene details for display (`StashSceneDetails`,
  `StashClient.sceneDetails(id:)`), the Stash-to-local path map (`StashPathMap`), play-activity bookkeeping
  (`StashActivity`, `StashActivityRequest`), the queue step gate (`QueueStepGate`) and the SMB share mounter
  (`ShareMounter`, links NetFS).
- `StashKitUI`: `StashLibraryView`, the Stash WebUI in a web view, made once and kept so going back finds the same
  page; browser keys and buttons (⌘[ ⌘] ⌘R, back/forward, swipe; `goBack()` / `goForward()` for buttons the app reads
  itself), a load failure shown in place, `onPageLoaded` after each page load. It changes the page only through the
  `StashInterceptor`s the app gives it (a script injected at document start plus a handler for its bridge messages).
  `StashInterceptor.scenePlayer` puts the scene's cover and ▶ in place of Stash's player and hands the scene to the
  app (`StashScene`: id, file paths, resume point, whether it came from a list), and keeps Stash's queue so `step(_:)`
  can go to the next or previous scene.

## Galleries (Loupe)

- `StashClient.gallery(id:)` and `findGalleries(variables:page:perPage:)` give `StashGallery` (id, title, the folder
  or zip file path as Stash wrote it); `firstGalleryPath()` is for a settings check.
- `StashInterceptor.galleryOpener(onOpen:)` takes a plain left click on a gallery in any list (Grid, List, Wall) and
  hands the app a `StashGalleryPick`: the gallery's id and, when the page's last `FindGalleries` answer holds it,
  that request's variables and the gallery's index in the whole list. The script wraps `window.fetch` to see the
  request, so a list's search, sort and criteria come along as the page sent them.
- `StashGalleryList` steps through that list page by page (skipping galleries without a path; `.end` at its ends).
- `StashLibraryView.navigate(to:)` moves the page to a path without a reload (a virtual gallery's own page).

## Tests

```sh
swift test
```

The scene fixture in `Tests/StashKitTests/Fixtures/find-scene.json` has the shape of a live `findScene` answer with
invented content.

## License

MIT — see [LICENSE](LICENSE).
