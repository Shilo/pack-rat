# PackRat

PackRat is a runtime-first Godot addon for downloadable PCK/ZIP content packs.
The happy path is intentionally small:

```gdscript
var result := await PackRat.prepare("https://example.com/packs/hub.pck")
```

PackRat downloads to `user://packrat`, keeps stable cache entries separate from
temporary `.part` files, freshness-checks cached content with HTTP metadata when
servers expose it, and mounts PCK/ZIP files with
`ProjectSettings.load_resource_pack(..., false)` by default.

No `EditorPlugin`, autoload, or project setting is required for runtime use.
`PackRat.prepare()` creates a `PackRatService` node under the scene tree root on
first use. Projects that want dependency injection can create their own service
node and call `PackRat.use_service(service)`.

## Options

```gdscript
var options := PackRatOptions.new()
options.id = "hub"
options.entry_path = "res://dlc/hub/main.tscn"
options.expected_sha256 = "..."

var result := await PackRat.prepare("https://example.com/packs/hub.pck", options)
```

Important defaults:

- `cache_dir = "user://packrat"`
- `replace_files = false`
- `.pck` and `.zip` URLs mount as resource packs
- unknown extensions download as cached files
- `allow_unverified_remote = true` for the one-URL development path

HTTP `ETag`, `Last-Modified`, and `Content-Length` support freshness decisions,
but they are not cryptographic integrity. Set `expected_sha256` or
`allow_unverified_remote = false` when PackRat should reject unverified remote
content.

## Extension Points

The public API stays simple, but the internals are subclassable:

- `PackRatSourceResolver`
- `PackRatFreshnessChecker`
- `PackRatCacheStore`
- `PackRatValidator`
- `PackRatInstaller`

Assign custom instances on `PackRatOptions` for one call, or configure a custom
`PackRatService` and pass it to `PackRat.use_service(service)`.
