# PackRat Demo Design Plan

Status: design spike, not implemented yet.

Date: 2026-06-11

## Goal

Replace the current `examples/` command-line style scene with one polished,
WebGL-friendly demo that shows PackRat's real value:

- the base export is tiny and only contains the shell UI;
- meaningful scenes/content are absent from the initial export;
- at runtime, PackRat downloads, caches, mounts, and opens remote resource packs;
- users can see progress, cancel an in-flight download, retry, clear cache, and
  observe a fast cached reload;
- the demo uses at least two remote resource packs.

The implementation should rename `examples/` to `demo/` and make the main scene
`demo/demo.tscn`.

## Recommended Concept

Build a single app-style showcase called **PackRat Portal**.

The base project exports only a lightweight portal UI with two or three content
cards. Each card represents downloadable content. Clicking a card starts a
PackRat request, shows progress, allows cancellation, then opens the mounted
scene inside the portal.

This is better than a full game or a generic mod loader for the first demo:

- A pure game hides the API story behind gameplay.
- A mod loader implies catalogs, dependency solving, manifests, and provider
  systems that PackRat intentionally does not provide.
- A portal/gallery makes the product truth obvious: "the shell is here, the
  content arrives later."

## Demo Packs

Use two packs so the demo proves both PCK and ZIP behavior.

| Pack | File | Format | Entry path | Purpose |
| --- | --- | --- | --- | --- |
| Warehouse | `packrat-demo-warehouse.pck` | PCK | `res://packrat_demo/warehouse/main.tscn` | A playful physics scene using simple boxes based on the PackRat icon palette. |
| Gallery | `packrat-demo-gallery.zip` | ZIP | `res://packrat_demo/gallery/main.tscn` | A UI/content scene with generated bulky placeholder assets to show app/content-pack use. |

Both packs should use unique namespaced `res://packrat_demo/...` paths. The demo
should set `replace_files = false` for showcase loads so the packs cannot
override the base UI by accident.

No dedicated artwork is required. Use simple Godot UI, generated shapes,
generated placeholder textures, and the existing PackRat icon palette.

## User Experience

The demo should open directly to the portal.

Each card should show:

- pack name;
- format, PCK or ZIP;
- source URL type, such as GitHub Release or GitHub Pages mirror;
- current state: not loaded, downloading, mounted, cache hit, failed, canceled;
- progress bar with downloaded bytes and total bytes when known;
- buttons for load, cancel, open, and clear cache.

When a pack finishes:

- show `PackRatResult.status`;
- show whether it came from cache;
- show the local cached path;
- show warnings if present;
- load the entry scene with `result.load_entry_scene()` into an in-app preview
  area or use `result.change_scene_to_entry()` for a full scene transition mode.

The first load should feel like a real download. A repeated load should be
noticeably fast, proving cache behavior.

## PackRat API Surface To Showcase

The demo should intentionally exercise the public API:

```gdscript
var options: PackRatOptions = PackRatOptions.new()
options.id = "warehouse"
options.entry_path = "res://packrat_demo/warehouse/main.tscn"
options.replace_files = false

var request: PackRatRequest = PackRat.load_resource_pack_async(url, options)
request.progress_changed.connect(_on_pack_progress_changed)
request.completed.connect(_on_pack_completed)

# Optional cancel button:
request.cancel()
```

Also include small, visible usage of:

- `PackRat.github_release_url(owner, repo, filename, tag)`;
- `PackRat.join_url(base_url, path)`;
- `PackRat.clear_cached_resource_pack(id_or_url, options)`;
- `PackRatResult.load_entry_scene()`;
- `PackRatResult.change_scene_to_entry()`, possibly as an alternate "Open full
  scene" path.

Do not add new PackRat runtime APIs just for the demo unless implementation
proves the existing public API is awkward.

## Hosting Decision

GitHub Releases should be the canonical artifact location because release assets
are easy for users to inspect and download.

However, the WebGL demo should not assume GitHub Release URLs are a reliable
browser runtime CDN until a real browser smoke test proves it. GitHub release
asset URLs redirect through GitHub-controlled asset hosts, and CORS headers are
not under this project's control.

Recommended first release shape:

1. Build the base Web demo.
2. Build `packrat-demo-warehouse.pck`.
3. Build `packrat-demo-gallery.zip`.
4. Upload the packs to a GitHub Release.
5. Mirror the same packs to GitHub Pages beside the Web demo.
6. Default the Web demo to the same-origin GitHub Pages pack URLs.
7. Include a toggle or code path that demonstrates `PackRat.github_release_url()`
   for native/editor users, or after a browser smoke confirms release URLs work.

This keeps the demo honest: GitHub Releases are used, but WebGL users get the
most reliable browser path.

## WebGL Constraints

Godot Web builds use browser networking rules. Cross-origin pack downloads need
CORS headers. Browser storage can also evict `user://`, so the demo must treat
PackRat cache as a performance cache, not durable truth.

Useful static host headers:

```http
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, HEAD, OPTIONS
Access-Control-Expose-Headers: ETag, Last-Modified, Content-Length, Content-Type
Content-Type: application/octet-stream
```

For immutable versioned packs, a CDN/static host can use:

```http
Cache-Control: public, max-age=31536000, immutable
```

For GitHub Pages same-origin hosting, CORS is less painful because the Web demo
and packs can live under the same site origin.

References:

- [Godot exporting PCK/ZIP packs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html)
- [ProjectSettings.load_resource_pack](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-method-load-resource-pack)
- [Godot Web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Godot command-line export](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
- [GitHub release asset links](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)
- [gh release upload](https://cli.github.com/manual/gh_release_upload)
- [MDN Access-Control-Expose-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Expose-Headers)

## Proposed Files

```text
demo/
  demo.tscn
  demo.gd
  pack_card.tscn
  pack_card.gd
  demo_catalog.gd
  theme.tres

demo_packs/
  warehouse/
    project.godot or source scene files
    packrat_demo/warehouse/main.tscn
  gallery/
    project.godot or source scene files
    packrat_demo/gallery/main.tscn

tools/
  build_demo_packs.ps1 or build_demo_packs.gd

.github/workflows/
  demo.yml
```

The final file layout can be smaller if implementation shows that `pack_card`
does not need its own scene/script. The priority is one good demo, not a mini
framework.

## Export And CI Plan

Add a committed `export_presets.cfg` with:

- one Web export preset for the base demo;
- one PCK pack preset for the warehouse pack;
- one ZIP pack preset for the gallery pack, if Godot's export preset workflow
  allows the desired output cleanly.

If ZIP export is awkward through presets, use a simple deterministic script to
create the ZIP from a prepared resource folder. The pack still must mount through
`ProjectSettings.load_resource_pack()` in tests and in the demo.

GitHub Actions workflow outline:

1. Trigger on tags and manual dispatch.
2. Install pinned Godot 4.6.x and matching export templates.
3. Import project assets headlessly.
4. Run PackRat smoke tests.
5. Export the base Web demo.
6. Export/build the two packs.
7. Upload build artifacts for debugging.
8. Create or update a GitHub Release.
9. Upload release assets:
   - `packrat-demo-web.zip`
   - `packrat-demo-warehouse.pck`
   - `packrat-demo-gallery.zip`
10. Deploy the Web demo and mirrored packs to GitHub Pages.

The workflow needs `permissions: contents: write` for release uploads and Pages
permissions for deployment.

## Testing Plan

Implementation should add automated coverage before the demo is considered done:

- native smoke: load both demo packs from a local HTTP server;
- native smoke: cancel a slowed request and verify `.part` cleanup;
- native smoke: repeated load reports cache hit and avoids extra GET;
- native smoke: `clear_cached_resource_pack()` removes future disk reuse;
- Web smoke: exported Web demo downloads and mounts both packs in a real browser;
- Web smoke: same-origin GitHub Pages pack URLs work;
- optional Web smoke: GitHub Release URLs work or are documented as editor/native
  only if CORS blocks them.

The Web smoke should be part of CI if practical. If CI browser setup is too slow
for first pass, keep a documented manual test checklist and add automation next.

## Non-Goals

Do not add these to the demo:

- client/server flow;
- authentication;
- mod manifests;
- catalogs fetched from a server;
- dependency resolution;
- provider plugins;
- dedicated custom artwork;
- resource-pack unload behavior;
- hot-update or same-path replacement demos.

These would make the showcase look like a different product than PackRat's MVP.

## Open Questions For Implementation

- Should the Web demo default to GitHub Pages mirror URLs while showing GitHub
  Release URLs in a "source" panel, or should it try Releases first and fall back
  to Pages?
- Should the preview area instance `result.load_entry_scene()` inside the portal,
  or should each pack use `result.change_scene_to_entry()` for a more obvious
  scene transition?
- How large should the generated demo payloads be so progress and cancellation
  are visible without making the demo annoying?
- Should the pack source folders live inside this repository, or should CI
  generate the heavy placeholder files on demand so the repo stays lightweight?

Recommended defaults:

- default to GitHub Pages mirror URLs for WebGL reliability;
- use in-portal preview for the main path and one "Open full scene" button to
  demonstrate `change_scene_to_entry()`;
- generate enough placeholder payload to make progress visible, but keep each
  pack well under 10 MB;
- generate bulky placeholder assets in CI rather than committing large binaries.
