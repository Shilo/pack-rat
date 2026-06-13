<img src="addons/pack_rat/icon.svg" alt="PackRat icon" width="128">

# PackRat

Your helpful little companion to fetch, stash, and mount your cheesy content.

PackRat is a lightweight Godot addon that downloads, verifies, caches, and
mounts DLC/content packs at runtime. Use it for worlds, mods, patches, skins,
episodes, asset bundles, or standalone downloadable files.

```gdscript
var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck")
```

No editor plugin, autoload, manifest, SHA sidecar, provider system, descriptor
object, or custom installer workflow is required.

PackRat is tuned for large runtime downloads. It uses larger native download
chunks than Godot's default, keeps transfer compression working, and uses the
browser's native download path on Web exports for near-browser download speed.
That means the same simple API can handle small patches, large DLC packs, and
Web-hosted worlds without special platform code in your game.

## Table of Contents

- [Install](#install)
- [Requirements](#requirements)
- [Build and Host Packs](#build-and-host-packs)
- [Quick Start](#quick-start)
- [What PackRat Does](#what-packrat-does)
- [What PackRat Does Not Do](#what-packrat-does-not-do)
- [API](#api)
- [Options](#options)
- [Results](#results)
- [Progress And Cancellation](#progress-and-cancellation)
- [Server Metadata Without Manifests](#server-metadata-without-manifests)
- [Offline-First Loads](#offline-first-loads)
- [Cache Behavior Matrix](#cache-behavior-matrix)
- [Web Export And CORS](#web-export-and-cors)
- [GitHub Release URLs](#github-release-urls)
- [Cache Cleanup](#cache-cleanup)
- [Security Notes](#security-notes)
- [Performance And Stability Notes](#performance-and-stability-notes)
- [Demo Scene](#demo-scene)
- [Smoke Tests](#smoke-tests)
- [Explicit Benchmarks](#explicit-benchmarks)
- [Troubleshooting](#troubleshooting)

## Install

Copy `addons/pack_rat/` into your Godot project.

Use PackRat scripts by class name:

```gdscript
var options: PackRatOptions = PackRatOptions.new()
var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck", options)
```

You do not need to enable a plugin in Project Settings.

## Requirements

PackRat targets Godot 4 and is currently tested with Godot 4.6.x. It uses
runtime `HTTPRequest` nodes and `ProjectSettings.load_resource_pack()`, so it
must run from a live `SceneTree`.

Build downloadable packs with the same Godot version family as your game. Godot
may reject packs produced by a newer incompatible engine version.

## Build and Host Packs

Create downloadable packs with Godot's pack export flow. The official docs cover
exporting `.pck` files and choosing between `.pck` and `.zip` pack formats:

- [Exporting packs, patches, and mods](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html)
- [PCK versus ZIP pack file formats](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html#pck-versus-zip-pack-file-formats)

Host the exported files as ordinary static files on your VPS, CDN, GitHub
Release, or GitHub Pages site:

```text
https://cdn.example.com/world_packs/hub.pck
https://cdn.example.com/world_packs/arena.zip
```

For Web exports, keep downloadable packs out of the initial game export when
they are meant to be fetched later. PackRat should download those packs from
your static host at runtime, not from files already bundled into the Web export.

## Quick Start

```gdscript
var options: PackRatOptions = PackRatOptions.new()
options.entry_path = "res://worlds/hub/main.tscn"

var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck", options)
if not result.ok:
	push_error(result.error)
	return

var error: Error = result.change_scene_to_entry()
if error != OK:
	push_error("Could not change to pack scene: %d" % error)
```

PackRat mounts the pack; your game can then load resources from the paths inside
that pack. Set an ID when the URL filename is not stable enough to be your cache
identity:

```gdscript
var options: PackRatOptions = PackRatOptions.new()
options.id = "hub"
options.entry_path = "res://worlds/hub/main.tscn"

var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck", options)
if not result.ok:
	push_error(result.error)
	return

var error: Error = result.change_scene_to_entry()
if error != OK:
	push_error("Could not change to pack scene: %d" % error)
```

## What PackRat Does

- Sends `HEAD` when a cached file exists and update checking is enabled.
- Compares `ETag`, `Last-Modified`, then reliable `Content-Length` when available.
- Can reuse cache by expected file metadata without a `HEAD` request.
- Can read local file size and modified time with `PackRat.file_metadata(path)`.
- Can run offline-first, using matching cache immediately and downloading only
  on cache miss.
- Downloads missing or stale packs to `user://pack_rat/tmp/*.part`.
- Moves successful downloads into flat versioned paths such as
  `user://pack_rat/<id>-<token>.pck`.
- Stores cache metadata in `user://pack_rat/cache.json`.
- Mounts `.pck` and `.zip` files with `replace_files=true` by default.
- Supports progress and cancellation through `PackRatRequest`.
- Can clear one cached pack or the full cache.
- Builds direct GitHub Releases URLs without calling the GitHub API.
- Keeps concurrent loads independent; duplicate simultaneous calls may each download.

## What PackRat Does Not Do

- No SHA-256 or signature validation.
- No manifests/catalogs.
- No GitHub API/provider integrations.
- No custom source resolver/cache/installer/validator classes.
- No unload/reload solution for already mounted same-path resources.
- No request de-duplication registry.

## API

```gdscript
var result: PackRatResult = await PackRat.load_resource_pack(url, options)
```

Downloads if needed, mounts the resource pack, and returns after completion.

```gdscript
var request: PackRatRequest = PackRat.load_resource_pack_async(url, options)
```

Starts the same work but returns a request handle immediately for progress and
cancellation.

```gdscript
var item_error: Error = PackRat.clear_cached_resource_pack(value, options)
var cache_error: Error = PackRat.clear_cache(options)
```

Deletes one cached pack or all PackRat cache files from disk.

```gdscript
var metadata: PackRatFileMetadata = PackRat.file_metadata(path)
var release_url: String = PackRat.github_release_url(owner, repo, filename, tag)
var static_url: String = PackRat.join_url(base_url, path)
```

Small helpers for server metadata workflows, direct GitHub Release asset URLs,
and static host URLs.

## Options

| Option | Default | Purpose |
| --- | --- | --- |
| `id` | `""` | Cache identity and filename prefix. Empty derives one from the URL filename. |
| `cache_dir` | `"user://pack_rat"` | Directory for `cache.json`, `.part` downloads, and cached packs. Must be a non-root `user://` path without `..` segments. |
| `replace_files` | `true` | Passed to `ProjectSettings.load_resource_pack()`. Allows the pack to override existing `res://` paths. |
| `offset` | `0` | Byte offset for embedded PCK files. ZIP packs must use `0`. |
| `entry_path` | `""` | Optional `res://` scene path copied into the result for caller convenience. PackRat only uses it when you call result entry-scene helpers. |
| `expected_size` | `0` | If greater than `0`, becomes part of cache identity and is checked against downloaded bytes. |
| `expected_modified_time` | `0` | If greater than `0`, becomes part of cache identity and is compared to `Last-Modified` when available. |
| `progress_total_size` | `0` | Optional non-validating byte total for progress bars when a platform cannot report a reliable HTTP body size. |
| `offline_first` | `false` | Uses a matching cached file immediately; downloads only on cache miss. |
| `request_headers` | `[]` | Extra headers for `HEAD` and `GET`. |
| `accept_gzip` | `true` | Lets native Godot `HTTPRequest` request gzip/deflate transfer compression. Web browsers already decode fetch bodies, so PackRat avoids a second Web `HTTPRequest` decode while still receiving browser-managed compression. |
| `timeout_seconds` | `120.0` | Finite HTTP timeout. |
| `download_chunk_size` | `8 * 1024 * 1024` | Bytes per native `HTTPRequest` read or Web `fetch()` write chunk. Defaults to a balanced 8 MiB chunk for DLC-sized files. Try 4 MiB or 16 MiB only after profiling your own host/device mix. PackRat clamps larger values to Godot's 16 MiB maximum. |
| `use_threads` | `false` | Lets native `HTTPRequest` use its worker thread when supported. Enable this after profiling a real native download that benefits from it. PackRat does not pass this through to Web `HTTPRequest`; Web exports use browser `fetch()` by default. |
| `use_web_fetch` | `true` | Uses PackRat's browser `fetch()` downloader for Web exports when available. Set `false` to force Godot `HTTPRequest`. |
| `capture_timings` | `false` | Fills `PackRatResult.timings_msec` for profiling. Leave off for the leanest production path. |
| `max_redirects` | `8` | Redirect limit for `HTTPRequest`. On Web `fetch()`, `0` disables redirects and positive values use the browser redirect behavior. |
| `always_download` | `false` | Forces a fresh download instead of using a matching cache file. |

Create options from server-provided file metadata:

```gdscript
var options: PackRatOptions = PackRatOptions.from_expected_metadata(expected_modified_time, expected_size)
var result: PackRatResult = await PackRat.load_resource_pack(url, options)
```

The argument order is `expected_modified_time`, then `expected_size`.

## Results

`PackRatResult.ok` is `true` when the pack is mounted and ready.

Useful fields:

| Field | Meaning |
| --- | --- |
| `status` | `"downloaded"`, `"cache_hit"`, or `"failed"`. |
| `from_cache` | `true` when no download was needed for this request. |
| `mounted` | `true` when Godot accepted the `.pck` or `.zip`. |
| `local_path` | Cached file path under `user://`. |
| `entry_path` | Copied from `PackRatOptions.entry_path`. |
| `warnings` | Non-fatal notes, such as missing comparable freshness headers. |
| `error` | Failure message when `ok == false`. |

Entry-scene helpers:

```gdscript
if result.entry_scene_exists():
	var scene: PackedScene = result.load_entry_scene()

var error: Error = result.change_scene_to_entry()
```

These helpers only use `PackRatOptions.entry_path`. PackRat does not discover
an unknown main scene from the mounted pack.

## Progress And Cancellation

```gdscript
var request: PackRatRequest = PackRat.load_resource_pack_async("https://example.com/packs/hub.pck")
request.progress_changed.connect(func(downloaded_bytes: int, total_bytes: int) -> void:
	if total_bytes > 0:
		print("%d / %d" % [downloaded_bytes, total_bytes])
	else:
		print("%d bytes" % downloaded_bytes)
)

# request.cancel()

await request.completed
if request.result.ok:
	print("Mounted: %s" % request.result.local_path)
elif request.result.was_canceled():
	print("Canceled")
```

Canceling a request completes it with a failed result. It also cancels the
active `HTTPRequest` when a download is already running.

## Server Metadata Without Manifests

Server-authoritative projects can pass expected file metadata instead of
creating a manifest or sidecar file.

On the server, read only file stats and send the compact values your game needs.
For a VPS or dedicated server, this is usually a real filesystem path:

```gdscript
var world_id: String = "hub"
var pack_path: String = "/srv/virtucade/world_packs/%s.pck" % world_id
var metadata: PackRatFileMetadata = PackRat.file_metadata(pack_path)
if not metadata.ok:
	push_error(metadata.error)
	return

rpc_id(peer_id, "prepare_world_transfer", world_id, metadata.modified_time, metadata.size)
```

On the client, derive URL and scene path by your own project convention:

```gdscript
@rpc("authority", "reliable")
func prepare_world_transfer(world_id: String, expected_modified_time: int, expected_size: int) -> void:
	var url: String = PackRat.join_url(world_pack_base_url, "%s.pck" % world_id)
	var options: PackRatOptions = PackRatOptions.from_expected_metadata(expected_modified_time, expected_size)
	options.entry_path = "res://server/worlds/%s/%s.tscn" % [world_id, world_id]

	var result: PackRatResult = await PackRat.load_resource_pack(url, options)
	if not result.ok:
		push_error(result.error)
		return

	var error: Error = result.change_scene_to_entry()
	if error != OK:
		push_error("World scene was not found after mounting pack: %s" % result.entry_path)
```

For example, your game can define this convention:

```text
world_id "hub" -> https://cdn.example.com/world_packs/hub.pck
```

When expected metadata is set, PackRat derives cache identity from the pack ID,
size, and modified time. A matching cached file is used immediately. Otherwise
the URL is downloaded and provided fields are checked independently.

For canonical URLs, `id` is optional because PackRat derives it from the
filename:

```text
https://cdn.example.com/worlds/hub.pck -> id "hub"
```

Set `options.id` for non-canonical URLs:

```gdscript
var options: PackRatOptions = PackRatOptions.from_expected_metadata(expected_modified_time, expected_size)
options.id = "hub"
var result: PackRatResult = await PackRat.load_resource_pack("https://cdn.example.com/download?id=hub", options)
```

```text
https://cdn.example.com/download?id=hub
https://cdn.example.com/latest.pck
```

Size is checked against the downloaded file bytes. Modified time is checked
against the server's `Last-Modified` header when it is available. If
`Last-Modified` is missing but expected size matches, the download is allowed
with a warning. If you only provide `expected_modified_time`, the server must
return a comparable `Last-Modified` header or PackRat cannot validate the
download.

## Offline-First Loads

```gdscript
var options: PackRatOptions = PackRatOptions.new()
options.offline_first = true
```

`offline_first` means a cache hit uses the cached file immediately and skips
remote update checks. A cache miss still downloads. This is not the same as
network-disabled mode.

## Cache Behavior Matrix

| Mode | Cache hit behavior | Cache miss behavior | Network check |
| --- | --- | --- | --- |
| Default | Sends `HEAD`, compares freshness, then uses cache if fresh or unknown. | Downloads. | `HEAD` on hit, `GET` on miss/stale. |
| `expected_size` or `expected_modified_time` | Uses matching cache identity immediately. | Downloads and validates provided fields. | No `HEAD`; `GET` only on miss. |
| `offline_first` | Uses cache immediately. | Downloads. | No `HEAD`; `GET` only on miss. |
| `always_download` | Ignores cache for the fresh request. | Downloads. | `GET`. |

## Web Export And CORS

For Godot Web exports, the pack server must allow browser downloads. If you want
HTTP freshness checks, expose the freshness headers too:

```text
Access-Control-Allow-Origin: *
Access-Control-Expose-Headers: ETag, Last-Modified, Content-Length, Content-Type
Cache-Control: no-cache
ETag: "..."
Last-Modified: Wed, 10 Jun 2026 20:15:00 GMT
Content-Length: 123456
Content-Type: application/octet-stream
```

If the browser cannot read `ETag` or `Last-Modified`, PackRat may treat
freshness as unknown and reuse the cached pack with a warning. Browser
`Content-Length` can describe compressed transfer bytes instead of decoded pack
bytes, so Web exports should use `expected_size` and/or `progress_total_size`
when they need exact byte totals.

In Web exports, `user://` cache lives in browser-managed storage. Browsers can
evict it, so treat PackRat's cache as a performance cache, not durable game
state. Your server or master-server metadata should remain the source of truth.

## GitHub Release URLs

```gdscript
var latest_url: String = PackRat.github_release_url("owner", "repo", "hub.pck")
var tagged_url: String = PackRat.github_release_url("owner", "repo", "hub.pck", "v1.2.0")
```

This helper only builds direct asset URLs. It does not call the GitHub API.

For ordinary static hosts or CDNs:

```gdscript
var url: String = PackRat.join_url("https://cdn.example.com/worlds/", "/hub.pck")
```

`join_url()` only handles slash cleanup. It does not fetch catalogs, list
directories, or encode provider-specific rules.

## Cache Cleanup

```gdscript
PackRat.clear_cached_resource_pack("hub")
PackRat.clear_cached_resource_pack("https://example.com/packs/hub.pck")
PackRat.clear_cached_resource_pack("hub-abc123.pck")
PackRat.clear_cache()
```

`clear_cached_resource_pack()` matches by URL, ID, cached filename, or cached
path. Cleanup is limited to non-root `user://` cache directories without `..`
segments.

Clearing cache only removes files from disk. Godot does not expose an API for
unloading a resource pack that is already mounted. PackRat removes matching
cache records but may keep mounted pack files on disk until the process exits.

## Security Notes

Downloaded packs are treated as authoritative content by default. Use trusted
URLs, because mounted packs can replace existing `res://` paths.

Set `replace_files=false` only when override behavior is unwanted.

HTTP metadata is useful for freshness, not authenticity. It answers "does this
look changed?" rather than "is this trusted content?"

`entry_path` is also not a validation feature. It is copied into
`PackRatResult` so caller code can keep its intended scene/resource path next to
the load result. Check that path with `ResourceLoader.exists()` or your own game
rules before using it.

## Performance And Stability Notes

- Downloads use a temporary `.part` path and move into cache only after success.
- Cache metadata is saved through a temporary JSON file with backup restore.
- `PackRatOptions` is copied when a request starts, so later option mutations do
  not affect an in-flight load.
- Repeated cache hits for the same ID, path, replace mode, and offset skip a
  duplicate mount call.
- Repeated expected-metadata or `offline_first` cache hits can use an exact
  in-process fast path after the first successful mount.
- Concurrent calls are independent by design. If two identical calls start at
  the same time, both may download.
- Native HTTPRequest progress polling happens once per frame while a GET is active.
- PackRat raises `HTTPRequest.download_chunk_size` above Godot's 64 KiB default
  because resource packs are DLC-sized files, not small API responses. It
  defaults to a balanced 8 MiB chunk and clamps larger values to Godot's 16 MiB
  engine maximum. In repeated tests, 8 MiB was the best default because 16 MiB
  can reduce callback overhead but may lose that gain to larger memory copies or
  longer single-step stalls. Treat 4 MiB and 16 MiB as opt-in profiling knobs.
- PackRat exposes native `HTTPRequest` worker threads through
  `PackRatOptions.use_threads`, but leaves them off by default. In repeated
  GitHub Pages tests, the threaded path was not consistently faster than the
  default native path.
- PackRat keeps gzip/deflate transfer compression enabled for native
  `HTTPRequest`. Web browsers decode fetch bodies before Godot reads them, so
  PackRat disables Web `HTTPRequest`'s extra decode step and still caches normal
  raw PCK/ZIP bytes.
- Web exports use a browser `fetch()` fast path for file downloads because
  Godot's Web HTTP client cannot progress more than once per frame. This is on
  by default through `PackRatOptions.use_web_fetch`, and can be disabled to
  compare against Godot `HTTPRequest`. It is much faster for large packs, but
  still uses browser and WebAssembly memory while chunks are handed to Godot.
  Web `fetch()` writes chunks using `download_chunk_size`, so the normal
  `.part` download path is shared with native `HTTPRequest`. Progress UI
  callbacks are rate-limited to 2 FPS to avoid bridge spam without slowing the
  actual browser download. The final progress callback still reports the exact
  completed byte count.
- `capture_timings` is opt-in so normal loads avoid profiling dictionary and
  timestamp overhead.
- `timeout_seconds` is finite by default so stalled downloads fail.
- If a fresh download would target an already-mounted cache path, PackRat keeps
  the mounted file and stores the new download at a unique cache path. It warns
  when a different pack is mounted for the same ID.
- Load packs before loading or preloading resources they are meant to replace.
  Godot may keep already-loaded scenes, scripts, and resources in memory, so a
  late-mounted pack does not behave like a clean restart.

## Demo Scene

```powershell
godot --path . --scene "res://demo/demo.tscn"
```

PackRat ships with a Web-friendly showcase scene called PackRat Portal. It uses
a tiny base scene and two editor-authored remote packs:

- `packrat-demo-warehouse.pck`, about 10 MiB.
- `packrat-demo-gallery.zip`, about 16 MiB.

In Web builds, the demo includes a `Downloader` selector to compare the default
browser `fetch()` path against Godot's `HTTPRequest` path. Native/editor runs
hide this selector because they always use Godot `HTTPRequest`.

The demo intentionally leaves `expected_size` and `expected_modified_time`
unset, but enables `offline_first` so repeated loads reuse the matching cached
pack immediately without a `HEAD` check. That keeps the showcase snappy while
still demonstrating the normal download, cache, mount, progress, cancel, and
clear-cache APIs.

Export the demo packs locally:

```powershell
godot --headless --path . --export-pack "Warehouse DLC" "build/packs/packrat-demo-warehouse.pck"
godot --headless --path . --export-pack "Gallery DLC" "build/packs/packrat-demo-gallery.zip"
godot --headless --path . --script "tools/demo_pack_catalog.gd" -- --output-dir=build/packs
```

This writes local demo packs to `build/packs/` using the `Warehouse DLC` and
`Gallery DLC` export presets, then updates the committed demo catalog size and
version tokens. The pack source scenes live in `demo/packs/` so they are
visible in the Godot editor. The Web export excludes `demo/packs/*`, then
PackRat mounts those paths back at runtime.

The demo pack presets enable both desktop and mobile Web VRAM texture
compression targets. This makes the PCK/ZIP exports larger when they contain
VRAM-compressed textures, but better demonstrates one universal Web pack that
can run on desktop and mobile browsers.

The demo DLC presets use Godot's `Export as dedicated server` resource mode only
to access per-folder `Keep` and `Remove` export behavior. The presets keep
`dedicated_server=false` and do not use `Strip Visuals`, so the exported packs
remain normal runtime content packs.

CI uses the same export presets, syncs the demo catalog to the exported
artifacts, and passes that exported pack directory into the demo smoke test.
This keeps Web deployments aligned even when ZIP metadata differs slightly
between operating systems:

```powershell
godot --headless --path . --script "tools/demo_pack_catalog.gd" -- --output-dir=build/packs
godot --headless --path . --scene "res://tests/pack_rat_demo_smoke.tscn" -- --pack-dir=build/packs
```

When exported for Web, the demo resolves pack URLs against the current page's
same-origin `packs/` folder. Native/editor runs default to the canonical GitHub
Pages mirror. For local manual testing against freshly built packs, start a
static server:

```powershell
python -m http.server 18924 --directory build
```

Then pass a pack base URL:

```powershell
godot --path . --scene "res://demo/demo.tscn" -- --pack-base-url=http://127.0.0.1:18924/packs --auto-load=warehouse,gallery --quit-when-done
```

Useful demo CLI args:

| Arg | Purpose |
| --- | --- |
| `--pack-base-url=...` | Static URL base for mirrored demo packs. |
| `--source=pages` | Use same-origin/static-host URLs. |
| `--source=github_release` | Use GitHub Release asset URLs for native/editor testing. Browser Web exports should use `pages` because GitHub release redirects do not provide game-friendly CORS headers. |
| `--release-tag=...` | GitHub Release tag for demo packs. |
| `--auto-load=warehouse,gallery` | Load one or more packs after startup. |
| `--quit-when-done` | Exit after auto-load finishes. |

## Smoke Tests

```powershell
godot --headless --path . --scene "res://tests/pack_rat_component_smoke.tscn"
godot --headless --path . --scene "res://tests/pack_rat_http_pck_smoke.tscn"
godot --headless --path . --scene "res://tests/pack_rat_http_zip_smoke.tscn"
godot --headless --path . --scene "res://tests/pack_rat_pck_hot_update_probe.tscn"
godot --headless --path . --scene "res://tests/pack_rat_demo_smoke.tscn"
```

These smokes cover local metadata reads, `expected_size`,
`expected_modified_time`, cache hits without `HEAD`/`GET`, changed metadata
redownloads, missing `Last-Modified` warnings, offline-first cache reuse,
independent concurrent loads, progress/cancel signals, fast-cache cancellation,
request headers, redirects, timeouts, `replace_files=false`, cache clearing,
PCK mounting, ZIP mounting, demo pack exporting, extensionless PCK URLs,
MMO-style scene existence, and Godot's same-path hot-update/resource-cache
behavior.

## Explicit Benchmarks

Benchmarks are intentionally not part of the automatic CI smoke path because
download timing depends on the runner, CDN edge, OS file cache, browser, and
frame rate. Run them explicitly when changing download code or tuning pack
hosting:

```powershell
godot --headless --path . --scene "res://tests/pack_rat_performance_smoke.tscn"
```

The Web download benchmark is also explicit. Export a Web build that starts
`res://tests/pack_rat_web_download_benchmark.tscn`, serve it over HTTP, and pass
`?url=<pack-url>&samples=<count>` to compare Web `fetch()` and Godot
`HTTPRequest` chunk sizes.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `PackRat only accepts HTTP(S) URLs.` | Local file paths are not supported by the load API. | Serve the pack over HTTP(S), or use `file_metadata()` only for metadata collection. |
| Freshness is always unknown. | Server or browser CORS is hiding `ETag`/`Last-Modified`, or the host cannot provide reliable freshness. | Expose freshness headers or use expected metadata. |
| `.zip` URL fails with nonzero offset. | Godot only supports offsets for PCK packs. | Keep `offset = 0` for ZIP packs. |
| Cache cleanup returns `ERR_INVALID_PARAMETER`. | `cache_dir` is root `user://`, outside `user://`, or contains `..`. | Use a dedicated directory such as `user://pack_rat`. |
| Web console prints `Failed to save IDB file system`. | Godot Web is syncing `user://` cache files to browser IndexedDB. DevTools may show a very large minified engine stack trace for one storage sync message. | Treat browser cache as a performance cache, keep using same-origin pack URLs, and clear the site's browser storage if IndexedDB gets wedged during testing. |
| Godot cannot mount the downloaded pack. | The pack may be invalid or built with an incompatible Godot version. | Rebuild the pack with the same Godot version family as the client. |
| Updated resources do not behave like a clean restart. | Godot cannot unload an already mounted pack. | Use versioned internal resource paths or restart between incompatible pack versions. |
