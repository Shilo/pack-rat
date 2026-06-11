# PackRat MVP

PackRat is a tiny runtime helper for downloading, caching, and mounting Godot
PCK/ZIP resource packs.

```gdscript
var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck")
```

The MVP is intentionally small:

- `pack_rat.gd`: the static `PackRat.load_resource_pack()` API and runtime logic.
- `pack_rat_request.gd`: progress, cancellation, and completion signals.
- `pack_rat_options.gd`: a few optional knobs.
- `pack_rat_result.gd`: a structured result object.
- `internal/`: small typed helpers for cache records and HTTP responses.

No editor plugin, manifest, SHA sidecar, provider system, descriptor object, or
custom installer workflow is required.

Downloaded packs are treated as authoritative content by default. Use trusted
URLs, because mounted packs can replace existing `res://` paths.

## What It Does

- Sends `HEAD` when a cached file exists.
- Compares `ETag`, `Last-Modified`, then `Content-Length` when available.
- Can reuse cache by expected file metadata without a `HEAD` request.
- Can run offline-first, using matching cache immediately and downloading only
  on cache miss.
- Downloads missing or stale packs to `user://pack_rat/tmp/*.part`.
- Moves successful downloads into `user://pack_rat/<id>/`.
- Stores cache metadata in `user://pack_rat/cache.json`.
- Mounts `.pck` and `.zip` files with `replace_files=true` by default.
- Supports progress and cancellation through `PackRatRequest`.
- Can clear one cached pack or the full cache.
- Builds direct GitHub Releases URLs without calling the GitHub API.
- De-dupes concurrent loads for the same cache identity.

## What It Does Not Do Yet

- No SHA-256 or signature validation.
- No manifests/catalogs.
- No GitHub API/provider integrations.
- No custom source resolver/cache/installer/validator classes.
- No unload/reload solution for already mounted same-path resources.

HTTP metadata is useful for freshness, not authenticity. It answers "does this
look changed?" rather than "is this trusted content?"

## Options

```gdscript
var options: PackRatOptions = PackRatOptions.new()
options.id = "hub"
options.entry_path = "res://worlds/hub/main.tscn"

var result: PackRatResult = await PackRat.load_resource_pack("https://example.com/packs/hub.pck", options)
if result.ok:
	var scene: PackedScene = load(result.entry_path)
```

For progress and cancellation:

```gdscript
var request: PackRatRequest = PackRat.load_resource_pack_async("https://example.com/packs/hub.pck")
request.progress_changed.connect(func(downloaded_bytes: int, total_bytes: int) -> void:
	print("%d / %d" % [downloaded_bytes, total_bytes])
)

# request.cancel()

await request.completed
if request.result.ok:
	print("Mounted: %s" % request.result.local_path)
```

Server-authoritative projects can pass file metadata instead of requiring a
manifest:

```gdscript
var options: PackRatOptions = PackRatOptions.new()
options.expected_size = pack_info.size
options.expected_modified_time = pack_info.modified_time

var result: PackRatResult = await PackRat.load_resource_pack(pack_info.url, options)
```

When expected metadata is set, PackRat derives cache identity from the pack ID,
size, and modified time. A matching cached file is used immediately; otherwise
the URL is downloaded and provided fields are checked independently. Size is
checked against the downloaded file bytes. Modified time is checked against the
server's `Last-Modified` header.

For PWA-style behavior:

```gdscript
var options: PackRatOptions = PackRatOptions.new()
options.offline_first = true
```

`offline_first` skips update checks when cache exists, but still downloads on
cache miss.

For GitHub Releases:

```gdscript
var latest_url: String = PackRat.github_release_url("owner", "repo", "hub.pck")
var tagged_url: String = PackRat.github_release_url("owner", "repo", "hub.pck", "v1.2.0")
```

For cache cleanup:

```gdscript
PackRat.clear_cached_resource_pack("hub")
PackRat.clear_cache()
```

Clearing cache only removes files from disk. Godot does not expose an API for
unloading a resource pack that is already mounted.

## Smoke Tests

```powershell
godot --headless --path . "res://tests/pack_rat_component_smoke.tscn"
godot --headless --path . "res://tests/pack_rat_http_pck_smoke.tscn"
godot --headless --path . "res://tests/pack_rat_http_zip_smoke.tscn"
```
