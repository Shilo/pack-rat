# PackRat MVP

PackRat is a tiny runtime helper for downloading, caching, and mounting remote
Godot `.pck` and `.zip` resource packs.

```gdscript
var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck")
```

No editor plugin, autoload, manifest, SHA sidecar, provider system, descriptor
object, or custom installer workflow is required.

## Table Of Contents

- [Install](#install)
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
- [Example Scene](#example-scene)
- [Smoke Tests](#smoke-tests)
- [Troubleshooting](#troubleshooting)

## Install

Copy `addons/pack_rat/` into your Godot project.

Use PackRat scripts by class name:

```gdscript
var options: PackRatOptions = PackRatOptions.new()
var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck", options)
```

You do not need to enable a plugin in Project Settings.

## Quick Start

```gdscript
var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck")
if not result.ok:
	push_error(result.error)
	return

var scene: PackedScene = load("res://worlds/hub/main.tscn")
get_tree().change_scene_to_packed(scene)
```

With options:

```gdscript
var options: PackRatOptions = PackRatOptions.new()
options.id = "hub"
options.entry_path = "res://worlds/hub/main.tscn"

var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck", options)
if result.ok:
	var scene: PackedScene = load(result.entry_path)
```

## What PackRat Does

- Sends `HEAD` when a cached file exists and update checking is enabled.
- Compares `ETag`, `Last-Modified`, then `Content-Length` when available.
- Can reuse cache by expected file metadata without a `HEAD` request.
- Can read local file size and modified time with `PackRat.file_metadata(path)`.
- Can run offline-first, using matching cache immediately and downloading only
  on cache miss.
- Downloads missing or stale packs to `user://pack_rat/tmp/*.part`.
- Moves successful downloads into `user://pack_rat/<id>/`.
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
static func PackRat.load_resource_pack(url: String, options: PackRatOptions = PackRatOptions.new()) -> PackRatResult
```

Downloads if needed, mounts the resource pack, and returns after completion.

```gdscript
static func PackRat.load_resource_pack_async(url: String, options: PackRatOptions = PackRatOptions.new()) -> PackRatRequest
```

Starts the same work but returns a request handle immediately for progress and
cancellation.

```gdscript
static func PackRat.clear_cached_resource_pack(value: String, options: PackRatOptions = PackRatOptions.new()) -> Error
static func PackRat.clear_cache(options: PackRatOptions = PackRatOptions.new()) -> Error
```

Deletes one cached pack or all PackRat cache files from disk.

```gdscript
static func PackRat.file_metadata(path: String) -> PackRatFileMetadata
static func PackRat.github_release_url(owner: String, repo: String, filename: String, tag: String = "latest") -> String
static func PackRat.join_url(base_url: String, path: String) -> String
```

Small helpers for server metadata workflows, direct GitHub Release asset URLs,
and static host URLs.

## Options

| Option | Default | Purpose |
| --- | --- | --- |
| `id` | `""` | Cache folder name. Empty derives one from the URL filename. |
| `cache_dir` | `"user://pack_rat"` | Directory for `cache.json`, `.part` downloads, and cached packs. Must be a non-root `user://` path without `..` segments. |
| `replace_files` | `true` | Passed to `ProjectSettings.load_resource_pack()`. Allows the pack to override existing `res://` paths. |
| `offset` | `0` | Byte offset for embedded PCK files. ZIP packs must use `0`. |
| `entry_path` | `""` | Optional `res://` path copied into the result for caller convenience. |
| `expected_size` | `0` | If greater than `0`, becomes part of cache identity and is checked against downloaded bytes. |
| `expected_modified_time` | `0` | If greater than `0`, becomes part of cache identity and is compared to `Last-Modified` when available. |
| `offline_first` | `false` | Uses a matching cached file immediately; downloads only on cache miss. |
| `request_headers` | `[]` | Extra headers for `HEAD` and `GET`. |
| `timeout_seconds` | `120.0` | Finite HTTP timeout. |
| `max_redirects` | `8` | Redirect limit for `HTTPRequest`. |
| `always_download` | `false` | Forces a fresh download instead of using a matching cache file. |

Create options from a generic server payload:

```gdscript
var pack: Dictionary = route["pack"]
var options: PackRatOptions = PackRatOptions.from_pack_info(pack)
var result: PackRatResult = await PackRat.load_resource_pack(str(pack["url"]), options)
```

`from_pack_info()` recognizes `id`, `size`, `expected_size`,
`modified_time`, `expected_modified_time`, `entry_path`, and `offline_first`.
It intentionally ignores `url`; pass the URL directly to `load_resource_pack()`.

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
```

Canceling a request completes it with a failed result. It also cancels the
active `HTTPRequest` when a download is already running.

## Server Metadata Without Manifests

Server-authoritative projects can pass file metadata instead of creating a
manifest or sidecar file.

On the server, read only file stats and build a generic payload:

```gdscript
var metadata: PackRatFileMetadata = PackRat.file_metadata("user://world_packs/hub.pck")
if not metadata.ok:
	push_error(metadata.error)
	return {}

return metadata.to_pack_info(
	PackRat.join_url("https://example.com/world_packs", "hub.pck"),
	"hub",
	"res://worlds/hub/main.tscn"
)
```

On the client, copy those fields into options:

```gdscript
var options: PackRatOptions = PackRatOptions.from_pack_info(pack_info)
var result: PackRatResult = await PackRat.load_resource_pack(str(pack_info["url"]), options)
```

When expected metadata is set, PackRat derives cache identity from the pack ID,
size, and modified time. A matching cached file is used immediately. Otherwise
the URL is downloaded and provided fields are checked independently.

Size is checked against the downloaded file bytes. Modified time is checked
against the server's `Last-Modified` header when it is available. If
`Last-Modified` is missing but expected size matches, the download is allowed
with a warning.

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

If the browser cannot read `ETag`, `Last-Modified`, or `Content-Length`, PackRat
may treat freshness as unknown and reuse the cached pack with a warning. The
server metadata flow avoids that by passing `expected_size` and/or
`expected_modified_time`.

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
unloading a resource pack that is already mounted. If a pack is already mounted,
avoid clearing its file until you are done loading resources from it in the
current process.

## Security Notes

Downloaded packs are treated as authoritative content by default. Use trusted
URLs, because mounted packs can replace existing `res://` paths.

Set `replace_files=false` only when override behavior is unwanted.

HTTP metadata is useful for freshness, not authenticity. It answers "does this
look changed?" rather than "is this trusted content?"

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
- Progress polling happens once per frame while a GET is active.
- `timeout_seconds` is finite by default so stalled downloads fail.
- If a fresh download replaces a file at an already-mounted path, PackRat warns
  because Godot resource packs remain mounted for the process lifetime.

## Example Scene

```powershell
godot --path . --scene "res://examples/pack_rat_load_resource_pack_demo.tscn" -- --id=hub --local-pack-path=user://world_packs/hub.pck --pack-url=https://example.com/world_packs/hub.pck --entry-path=res://worlds/hub/main.tscn --quit-when-done
```

Useful CLI args:

| Arg | Purpose |
| --- | --- |
| `--pack-url=...` | Remote `.pck` or `.zip` URL. |
| `--local-pack-path=...` | Local file to read metadata from before loading. |
| `--id=...` | Cache ID. |
| `--entry-path=...` | Resource path to copy into the result. |
| `--expected-size=...` | Expected byte size. |
| `--expected-modified-time=...` | Expected Unix modified time. |
| `--offline-first` | Enable cache-hit-first behavior. |
| `--quit-when-done` | Exit after printing the result. |

## Smoke Tests

```powershell
godot --headless --path . --scene "res://tests/pack_rat_component_smoke.tscn"
godot --headless --path . --scene "res://tests/pack_rat_http_pck_smoke.tscn"
godot --headless --path . --scene "res://tests/pack_rat_http_zip_smoke.tscn"
godot --headless --path . --scene "res://tests/pack_rat_pck_hot_update_probe.tscn"
```

These smokes cover local metadata reads, `expected_size`,
`expected_modified_time`, cache hits without `HEAD`/`GET`, changed metadata
redownloads, missing `Last-Modified` warnings, offline-first cache reuse,
independent concurrent loads, progress/cancel signals, cache clearing, PCK
mounting, ZIP mounting, extensionless PCK URLs, repeated cache-hit performance,
and Godot's same-path hot-update/resource-cache behavior.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `PackRat MVP only accepts HTTP(S) URLs.` | Local file paths are not supported by the load API. | Serve the pack over HTTP(S), or use `file_metadata()` only for metadata collection. |
| Freshness is always unknown. | Server or browser CORS is hiding `ETag`, `Last-Modified`, or `Content-Length`. | Expose those headers or use expected metadata. |
| `.zip` URL fails with nonzero offset. | Godot only supports offsets for PCK packs. | Keep `offset = 0` for ZIP packs. |
| Cache cleanup returns `ERR_INVALID_PARAMETER`. | `cache_dir` is root `user://`, outside `user://`, or contains `..`. | Use a dedicated directory such as `user://pack_rat`. |
| Updated resources do not behave like a clean restart. | Godot cannot unload an already mounted pack. | Use versioned internal resource paths or restart between incompatible pack versions. |
