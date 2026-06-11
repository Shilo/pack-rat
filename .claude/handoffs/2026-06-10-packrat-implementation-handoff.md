# Handoff: PackRat Runtime DLC Addon

## Session Metadata

- Created: 2026-06-10
- Project: `C:\Programming_Files\Shilocity\Godot\pack-rat`
- Purpose: prepare the empty PackRat Godot project for implementation by adding
  research, a PackRat-specific spike, and a concrete implementation handoff.

## Current State Summary

This project is a minimal Godot repo intended to become **PackRat**, a reusable
runtime downloadable-content addon. No addon code has been implemented yet in
this handoff. The only intentional work completed so far is documentation:

- copied prior DLC/world-pack research into `docs/reference/`;
- copied the PackRat branding/API research attachment into `docs/reference/`;
- wrote `docs/packrat-spike.md`;
- wrote this implementation handoff.

The next agent should build the addon from these docs, not from assumptions
about VirtuCade or world servers.

## Important Context

PackRat's main product promise is simplicity:

```gdscript
var result := await PackRat.prepare("https://example.com/packs/hub.pck")
```

The first version should make that one-line URL call work. Earlier research
contains stronger recommendations around manifests, sidecar hashes, provider
digests, and descriptor dictionaries. Those are still useful later, but they are
not the north star for PackRat v1.

The user explicitly wants:

- simple high-level API above all else;
- remote PCK URL as the first argument;
- everything else inferred where possible;
- no required manifest;
- no required extra `.sha256` file for the first revision;
- dynamic version/date/freshness comparison if the server exposes it;
- optional typed options class instead of raw option dictionaries;
- no required enabled editor plugin;
- addon must be generic and not know about worlds.

The user does not want this handoff agent to create a marketplace-ready asset
yet. The current assignment was only to prepare docs and handoff material. The
next implementation agent can begin coding.

## Architecture Overview

PackRat should be a runtime-first Godot addon under:

```text
res://addons/packrat/
```

Downloaded runtime content belongs under:

```text
user://packrat/
```

Do not write downloaded PCKs into `res://addons/packrat/`.

Core runtime architecture:

```text
PackRat static facade
  -> PackRatService Node
       -> HEAD/GET/download HTTP helpers
       -> cache DB
       -> installer/mounter
       -> in-flight request dedupe
       -> result/progress reporting
```

The static facade may auto-create `PackRatService` under the scene tree root on
first use. An explicit autoload can be supported later for users who want more
control, but it must not be required for the happy path.

## Critical Files

| File | Purpose |
|------|---------|
| `docs/packrat-spike.md` | Main PackRat design spike. Read first. |
| `docs/reference/packrat-addon-branding-research.md` | User-provided PackRat naming, API, mascot, and broader deployment notes. |
| `docs/reference/universal-dlc-addon-spike.md` | Prior generic DLC research. Useful, but heavier than desired for PackRat v1. |
| `docs/reference/dynamic-world-pck-streaming-research.md` | VirtuCade/world-pack background. Do not overfit PackRat to this. |
| `project.godot` | Minimal Godot project state. |

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Product name is `PackRat`. | User chose the name; branding research supports it. |
| Primary verb is `prepare()`. | Avoids ambiguous `ensure_*`; covers cache hit, download, mount, and ready states. |
| Primary v1 input is a URL string. | User wants `PackRat.prepare(remote_pck_url)` to handle the common path. |
| Options should be typed. | User prefers a class over dictionaries for optional metadata/config. |
| No required editor plugin. | Runtime addon should work by loading scripts normally; editor tooling is optional later. |
| No required manifest in v1. | Static PCK hosting should work with just a URL. |
| No required sidecar hash in v1. | Freshness should use HTTP metadata when possible; hashes become optional integrity upgrades. |
| `replace_files=false` default. | Universal addon should not silently override base game resources. |

## Files Modified

| File | Change |
|------|--------|
| `docs/packrat-spike.md` | Added PackRat-specific design spike focused on the one-URL API and typed options. |
| `docs/reference/universal-dlc-addon-spike.md` | Copied prior universal DLC research for background. |
| `docs/reference/dynamic-world-pck-streaming-research.md` | Copied prior VirtuCade world-pack research for background. |
| `docs/reference/packrat-addon-branding-research.md` | Copied user-provided PackRat naming, API, deployment, and icon research. |
| `.claude/handoffs/2026-06-10-packrat-implementation-handoff.md` | Added this implementation handoff. |

## API Target

Minimum happy path:

```gdscript
var result := await PackRat.prepare("https://cdn.example.com/packs/hub.pck")
```

Typed options path:

```gdscript
var options := PackRatOptions.new()
options.id = "hub"
options.entry_path = "res://server/worlds/hub/hub.tscn"

var result := await PackRat.prepare("https://cdn.example.com/packs/hub.pck", options)
```

The v1 result should be a typed object:

```gdscript
if result.ok:
	print(result.status)
	print(result.from_cache)
	print(result.local_path)
```

Avoid public APIs named `ensure_*`.

## Implementation Requirements

Agent operating instructions:

- Work fully autonomously toward a streamlined, lightweight DLC/PCK addon that is
  extremely easy to use.
- Challenge this entire design before and during implementation. Run small
  research spikes for uncertain areas instead of blindly following the docs.
- Use the Godot MCP when available, and research Godot's addon system, runtime
  resource packs, Web export behavior, `HTTPRequest`, and `ProjectSettings`.
- Avoid requiring an `EditorPlugin` for runtime use. Editor tooling can exist
  later, but PackRat's core must work without enabling a plugin.
- Prefer subclassable components for extension points, such as source resolvers,
  freshness checkers, installers, cache stores, and validators. Keep the public
  API simple even if internals are modular.
- Follow conventional commit style and commit regularly in small coherent units.
- Follow Godot's GDScript style guide.

Useful Godot documentation:

- Godot 3.2 PCK export docs:
  `https://docs.godotengine.org/en/3.2/getting_started/workflow/export/exporting_pcks.html`
- Godot 4.4 GDScript style guide:
  `https://docs.godotengine.org/en/4.4/tutorials/scripting/gdscript/gdscript_styleguide.html`
- Godot editor plugin docs:
  `https://docs.godotengine.org/en/stable/tutorials/plugins/editor/making_plugins.html`

Build these first:

1. Future PackRat facade script
   - `class_name PackRat`
   - static `prepare(url: String, options: PackRatOptions = null)`
   - lazy service creation

2. Future typed options script
   - typed properties, no mandatory constructor complexity
   - default `cache_dir = "user://packrat"`
   - default `replace_files = false`
   - default install mode auto-detected from extension

3. Future typed result script
   - typed status/result object
   - include `ok`, `status`, `from_cache`, `mounted`, `local_path`,
     `source_url`, `final_url`, `entry_path`, HTTP metadata, and `error`

4. Future runtime service script
   - owns HTTPRequest nodes
   - runs HEAD freshness check where possible
   - downloads with `HTTPRequest.download_file`
   - writes `.part` files first
   - commits to cache only after basic validation
   - mounts resource packs
   - dedupes concurrent calls by cache key

5. Cache file:
   - `user://packrat/cache.json`
   - stores URL, final URL, ETag, Last-Modified, Content-Length, local path,
     and timestamp

6. Minimal demo/test scene:
   - calls `PackRat.prepare(url)`
   - demonstrates download, cache hit, and mount

## Freshness Strategy

The first revision should try dynamic freshness before requiring hashes.

Preferred default:

1. Infer cache key from URL/final URL and filename.
2. If cache record exists and file exists, send `HEAD` to remote URL.
3. Compare `ETag`, `Last-Modified`, and `Content-Length` when available.
4. If validators match, use cache.
5. If validators changed/missing/HEAD failed, download according to options.
6. If optional `expected_sha256` is set, verify it.
7. If no hash is available, still allow the v1 URL path, but log that integrity
   is unverified.

Be precise in docs and logs: HTTP metadata can support freshness checks, but it
does not prove cryptographic integrity.

## Assumptions Made

- The target repo is intentionally minimal and should stay documentation-only
  until the next implementation task starts.
- PackRat v1 can prefer convenience over cryptographic integrity, as long as
  docs/logs are honest about unverified remote content.
- Plain HTTP/static hosting is the first supported source. Provider APIs are
  later work.
- The initial implementation can support PCK/ZIP resource-pack mounting before
  generic file and ZIP extraction modes.

## Potential Gotchas

- `ProjectSettings.load_resource_pack()` mounts local `.pck` or `.zip` files
  into `res://`; there is no obvious public unload API. Treat mounts as
  process-lifetime.
- Mounted packs can override existing resources when `replace_files=true`.
  Default to `false`.
- `HTTPRequest` is a `Node`; a static API still needs a service node.
- Godot Web exports are subject to browser CORS. `ETag` may not be readable
  unless the server exposes it.
- `HEAD` may fail on some hosts; PackRat needs a fallback policy.
- `user://` persistence in Web exports depends on browser storage.
- Do not make GitHub Releases a v1 provider before testing browser redirects and
  CORS.

## Verification Plan

Before calling v1 done:

1. Local HTTP server serves a test PCK.
2. First `PackRat.prepare(url)` downloads and mounts.
3. Second `PackRat.prepare(url)` hits cache.
4. Remote file timestamp/size changes and PackRat redownloads.
5. Failed download leaves old cache untouched.
6. Two concurrent `prepare(url)` calls produce one network download.
7. `replace_files=false` default is verified.
8. Web export test runs same-origin with a PCK URL.

## Immediate Next Steps

1. Read `docs/packrat-spike.md` completely.
2. Create `addons/packrat/` runtime files only.
3. Implement the one-URL happy path first.
4. Add typed options and typed result.
5. Add a tiny local demo/test scene.
6. Test cache hit and stale detection before adding any provider-specific code.

## Deferred Work

- Editor plugin UI.
- GitHub Releases provider.
- GitHub Pages-specific provider.
- Catalog manifests.
- ZIP extraction beyond resource-pack mounting.
- Cache eviction policy.
- Signed packs or encryption.
- Marketplace packaging.
- Icon/SVG work beyond preserving the branding notes.

## Related Resources

- `docs/packrat-spike.md`
- `docs/reference/packrat-addon-branding-research.md`
- `docs/reference/universal-dlc-addon-spike.md`
- `docs/reference/dynamic-world-pck-streaming-research.md`
