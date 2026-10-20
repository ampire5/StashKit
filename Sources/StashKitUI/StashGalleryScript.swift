import Foundation

/// A gallery picked in Stash's WebUI: its id, and where in a list it was picked, if the list
/// is the page's last `FindGalleries` answer.
public struct StashGalleryPick: Equatable, Sendable {
    public let id: String
    public let list: StashGalleryListContext?
    /// A ⌘-click or middle click (the script takes it only with `interceptsNewTabClicks`): the app is asked for a new
    /// tab, not this one.
    public let newTab: Bool
    /// A ⇧-click or ⇧ + middle click (taken only with `interceptsNewTabClicks` too): the app is asked for a new window.
    public let newWindow: Bool

    /// A pick made by the app itself (Loupe's Home opens a recent gallery as a click in Stash would).
    public init(id: String, list: StashGalleryListContext?, newTab: Bool = false, newWindow: Bool = false) {
        self.id = id
        self.list = list
        self.newTab = newTab
        self.newWindow = newWindow
    }

    public init?(message body: Any) {
        guard let body = body as? [String: Any], body["type"] as? String == "gallery",
              let id = body["id"] as? String else { return nil }
        self.id = id
        newTab = body["newTab"] as? Bool ?? false
        newWindow = body["newWindow"] as? Bool ?? false
        if let list = body["list"] as? [String: Any], let index = (list["index"] as? NSNumber)?.intValue,
           let variables = list["variables"], JSONSerialization.isValidJSONObject(variables),
           let json = try? JSONSerialization.data(withJSONObject: variables) {
            self.list = StashGalleryListContext(variables: json, index: index,
                                                count: (list["count"] as? NSNumber)?.intValue)
        } else {
            self.list = nil
        }
    }
}

/// The script behind `StashInterceptor.galleryOpener` (selectors from Loupe's
/// docs/bench/2026-10-19-stash-probe.md). It wraps `window.fetch` to keep the page's recent `FindGalleries` answers
/// (variables, ids, count; newest first), and takes a plain left click on a gallery in a list — Grid (`.gallery-card`),
/// List (`td.title-data`, `td.cover_image-data`) or Wall (`.GalleryWallCard`, whose only link is in its footer) — away
/// from Stash: `{type: "gallery", id, list: {variables, index, count} | null, newTab, newWindow}` to the bridge
/// handler. A ⌘-click and a middle click are taken too, with `newTab: true`, and a ⇧-click and ⇧ + middle click (⌘⇧ as
/// well) with `newWindow: true`, when `interceptsNewTabClicks` (else they stay Stash's, as the other modifiers do). Clicks with another modifier, other buttons, the selection checkbox and other
/// links (popovers, the navbar) stay Stash's.
/// The list is the answer whose galleries are the ones on screen: Stash fills a page it has seen from its cache without
/// asking (Loupe's 2026-10-19 probe: the Galleries page again from the navbar, back, forward), so the last request is
/// not always the page's. Failing an exact match, the answer with the gallery and the most of the page's.
enum StashGalleryScript {
    static func source(interceptsNewTabClicks: Bool) -> String {
        template.replacingOccurrences(of: "NEW_TAB_CLICKS", with: interceptsNewTabClicks ? "true" : "false")
            .replacingOccurrences(of: "/*MIDDLE_CLICK*/", with: interceptsNewTabClicks ? middleClick : "")
    }

    /// A middle click on a gallery: `mousedown` is Stash's no more (no autoscroll), `auxclick` is the pick.
    private static let middleClick = #"""
      document.addEventListener("mousedown", (event) => {
        if (event.button !== 1 || !pickedID(event)) return;
        event.preventDefault();
        event.stopPropagation();
      }, true);
      document.addEventListener("auxclick", (event) => {
        if (event.button === 1 && !event.metaKey && !event.ctrlKey && !event.altKey) {
          take(event, !event.shiftKey, event.shiftKey);
        }
      }, true);
    """#

    private static let template = #"""
    (() => {
      if (window.__stashGalleryOpener) return;
      window.__stashGalleryOpener = true;
      const takesNewTabClicks = NEW_TAB_CLICKS;
      const post = (message) => window.webkit.messageHandlers.framescrub.postMessage(message);
      const answers = [];   // { key, variables, ids, count }, newest first
      const remember = (variables, ids, count) => {
        const key = JSON.stringify(variables);
        const old = answers.findIndex((a) => a.key === key);
        if (old >= 0) answers.splice(old, 1);
        answers.unshift({ key, variables, ids, count });
        if (answers.length > 50) answers.pop();
      };
      const originalFetch = window.fetch;
      window.fetch = async function (input, init) {
        const response = await originalFetch.apply(this, arguments);
        try {
          const body = init && typeof init.body === "string" ? JSON.parse(init.body) : null;
          if (body && body.operationName === "FindGalleries") {
            const json = await response.clone().json();
            const found = (json && json.data && json.data.findGalleries) || {};
            const ids = (found.galleries || []).map((g) => String(g.id));
            remember(body.variables || {}, ids, typeof found.count === "number" ? found.count : null);
          }
        } catch (e) {}
        return response;
      };
      const cards = ".gallery-card, .GalleryWallCard, td.title-data, td.cover_image-data";
      const galleryID = (card, target) => {
        let link = target ? target.closest("a[href]") : card.querySelector('a[href^="/galleries/"]');
        if (!link && card.classList.contains("GalleryWallCard")) link = card.querySelector('a[href^="/galleries/"]');
        if (!link) return null;
        const match = /^\/galleries\/(\d+)$/.exec(link.getAttribute("href") || "");
        return match ? match[1] : null;
      };
      const onScreen = () => {
        const ids = [];
        for (const card of document.querySelectorAll(cards)) {
          const id = galleryID(card, null);
          if (id && !ids.includes(id)) ids.push(id);
        }
        return ids;
      };
      const listFor = (id) => {
        const shown = onScreen(), seen = new Set(shown);
        let best = null, score = -1;
        for (const answer of answers) {
          if (!answer.ids.includes(id)) continue;
          if (answer.ids.length === shown.length && answer.ids.every((x, i) => x === shown[i])) { best = answer; break; }
          const s = answer.ids.filter((x) => seen.has(x)).length;
          if (s > score) { best = answer; score = s; }
        }
        if (!best) return null;
        const filter = best.variables.filter || {};
        const index = ((filter.page || 1) - 1) * (filter.per_page || 25) + best.ids.indexOf(id);
        return { variables: best.variables, index, count: best.count };
      };
      const pickedID = (event) => {
        const target = event.target;
        if (!target || !target.closest) return null;
        const card = target.closest(cards);
        return card ? galleryID(card, target) : null;
      };
      const take = (event, newTab, newWindow) => {
        const id = pickedID(event);
        if (!id) return;
        event.preventDefault();
        event.stopPropagation();
        post({ type: "gallery", id, list: listFor(id), newTab, newWindow });
      };
      document.addEventListener("click", (event) => {
        if (event.button !== 0 || event.ctrlKey || event.altKey) return;
        if ((event.metaKey || event.shiftKey) && !takesNewTabClicks) return;
        take(event, event.metaKey && !event.shiftKey, event.shiftKey);
      }, true);
      /*MIDDLE_CLICK*/
    })();
    """#
}

extension StashInterceptor {
    /// Takes a click on a gallery in any Stash list and hands it to the app (`onOpen`) instead of opening the
    /// gallery's page. `interceptsNewTabClicks`: a ⌘-click and a middle click are taken too, with `newTab` set,
    /// and a ⇧-click and ⇧ + middle click with `newWindow` set.
    public static func galleryOpener(interceptsNewTabClicks: Bool = false,
                                     onOpen: @escaping (StashGalleryPick) -> Void) -> StashInterceptor {
        StashInterceptor(script: StashGalleryScript.source(interceptsNewTabClicks: interceptsNewTabClicks)) { body in
            guard let pick = StashGalleryPick(message: body) else { return false }
            onOpen(pick)
            return true
        }
    }
}
