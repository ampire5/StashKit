/// The script injected into Stash's WebUI. It replaces Stash's `ScenePlayer` through the plugin
/// API with the scene's cover and a ▶ that hands the scene to FrameScrub, and keeps the player's queue callbacks so
/// that the app can step through Stash's own queue (its filter, sort and pages).
///
/// Messages to the `framescrub` handler:
/// - `{type: "open", automatic, sceneID, paths, resumeTime, duration, hasQueue}` — a click on the cover
///   (`automatic: false`), or a scene that Stash opened with `autoplay=true` after a queue step (`automatic: true`);
/// - `{type: "no-bridge"}` — the page has no `PluginApi` (not Stash, or a Stash without the plugin API).
///
/// Kept as a string rather than a resource: `make-app.sh` copies resources, `swift run` has no bundle.
enum StashBridgeScript {
    static let handlerName = "framescrub"

    static let source = #"""
    (() => {
      if (window.__framescrubBridge) return;
      window.__framescrubBridge = true;
      const post = (message) => window.webkit.messageHandlers.framescrub.postMessage(message);
      const hasQueue = () => /[?&](qfp|qs)=/.test(location.search);
      const sceneMessage = (scene, automatic) => {
        const files = scene.files || [];
        return {
          type: "open", automatic, sceneID: String(scene.id), paths: files.map((f) => f.path),
          resumeTime: scene.resume_time || 0, duration: (files[0] && files[0].duration) || 0, hasQueue: hasQueue(),
        };
      };

      const install = (api) => {
        if (window.__framescrubInstalled || !api || !api.patch || !api.React) return;
        window.__framescrubInstalled = true;
        const React = api.React;
        const h = React.createElement;
        // Stash looks the patches up on every render, so a late registration still replaces the player.
        api.patch.instead("ScenePlayer", function (props) {
          const scene = props.scene;
          window.__framescrub = { next: props.onNext, previous: props.onPrevious };
          // A queue step from the app lands here with autoplay=true: hand the new scene over at once.
          React.useEffect(() => {
            if (props.autoplay && scene) post(sceneMessage(scene, true));
          }, [scene && scene.id]);
          if (!scene) return null;
          const path = scene.files && scene.files[0] ? scene.files[0].path : "";
          const screenshot = scene.paths && scene.paths.screenshot;
          return h("div", {
            className: "framescrub-cover",
            title: "Play in FrameScrub",
            onClick: () => post(sceneMessage(scene, false)),
            style: {
              position: "relative", width: "100%", height: "100%", minHeight: "240px", cursor: "pointer",
              background: "#000" + (screenshot ? ` url("${screenshot}") center / contain no-repeat` : ""),
            },
          },
            h("div", {
              style: {
                position: "absolute", left: "50%", top: "50%", width: "84px", height: "84px",
                margin: "-42px 0 0 -42px", borderRadius: "50%", background: "rgba(0,0,0,0.55)",
                border: "2px solid rgba(255,255,255,0.85)", color: "#fff", fontSize: "38px",
                lineHeight: "80px", textAlign: "center", paddingLeft: "6px", boxSizing: "border-box",
              },
            }, "▶"),
            h("div", {
              style: {
                position: "absolute", left: "8px", right: "8px", bottom: "6px", color: "rgba(255,255,255,0.6)",
                fontSize: "12px", textAlign: "center", overflow: "hidden", textOverflow: "ellipsis",
                whiteSpace: "nowrap", textShadow: "0 1px 2px #000",
              },
            }, path));
        });
      };

      // Stash assigns window.PluginApi while its modules load, before the first render: catch the assignment so
      // the player is replaced before a scene page ever shows it.
      if (window.PluginApi) {
        install(window.PluginApi);
      } else {
        let value;
        Object.defineProperty(window, "PluginApi", {
          configurable: true, enumerable: true,
          get: () => value,
          set: (v) => { value = v; install(v); },
        });
      }
      let tries = 0;
      const timer = setInterval(() => {
        if (window.__framescrubInstalled) { clearInterval(timer); return; }
        install(window.PluginApi);
        if (!window.__framescrubInstalled && ++tries >= 200) { clearInterval(timer); post({ type: "no-bridge" }); }
      }, 50);
    })();
    """#
}
