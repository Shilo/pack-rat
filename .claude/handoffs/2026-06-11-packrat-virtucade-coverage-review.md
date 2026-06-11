# PackRat VirtuCade Coverage And File Structure Handoff

Date: 2026-06-11

## Purpose

This handoff preserves the review context for PackRat's future VirtuCade and
multi-server-test integration work. It is not an instruction to immediately move
files. It documents the target structure and review constraints so a future
agent can challenge and implement the change deliberately when requested.

## Recovery Note

This handoff was recreated because the original
`.claude/handoffs/2026-06-11-packrat-virtucade-coverage-review.md` was not in
the committed Git history. The only committed handoff found in history was:

```text
.claude/handoffs/2026-06-10-packrat-implementation-handoff.md
```

Exact searches for the June 11 filename and the proposed `core/`, `request/`,
`cache/`, and `util/` wording did not find a committed copy.

## Current State

Current addon structure at the time of recreation:

```text
addons/pack_rat/
  pack_rat.gd
  pack_rat_options.gd
  pack_rat_result.gd
  pack_rat_request.gd
  pack_rat_file_metadata.gd

  internal/
    pack_rat_cache.gd
    pack_rat_cache_record.gd
    pack_rat_http_response.gd
    pack_rat_request_runner.gd
```

Important: no `core/`, `cache/`, `request/`, or `util/` folders are currently
implemented under `addons/pack_rat/`.

## Design Preference

The preferred future structure is namespace-style and feature-based, not based
on broad file types. Avoid `public/` and `internal/` folders. Avoid folders with
only one file when possible, except for `util/`, which is acceptable if it has a
clear rule.

Recommended target:

```text
addons/pack_rat/
  pack_rat.gd

  core/
    pack_rat_options.gd
    pack_rat_result.gd
    pack_rat_request.gd

  cache/
    pack_rat_cache.gd
    pack_rat_cache_record.gd

  request/
    pack_rat_request_runner.gd
    pack_rat_http_response.gd

  util/
    pack_rat_file_metadata.gd
```

Use `request/` singular, not `requests/`.

## `util/` Rule

Allow `util/`, but keep a strict boundary:

```text
util/ = optional helper APIs that are not the main loading pipeline
```

By that rule, `pack_rat_file_metadata.gd` belongs in `util/`. It helps
server-side metadata workflows, but it is not conceptually part of the main
download/cache/mount lifecycle.

Do not put these in `util/`:

```text
pack_rat_http_response.gd     # belongs to request/
pack_rat_request_runner.gd    # belongs to request/
pack_rat_cache.gd             # belongs to cache/
pack_rat_cache_record.gd      # belongs to cache/
```

Challenge: `util/` can become a junk drawer fast. Only put files there if they
are optional helper conveniences and do not own part of the main
download/cache/mount lifecycle.

## Migration Requirements

If this structure is implemented later:

- Move files only when explicitly asked.
- Update all preload paths in tests and examples.
- Preserve all current public class names and APIs.
- Do not add an `EditorPlugin`.
- Do not add PackRatService, DI, descriptors, provider/catalog systems, SHA
  sidecars, or game-specific VirtuCade logic as part of this file move.
- Keep PackRat lightweight and easy to read.
- Run the full smoke suite after moving files.

Suggested verification:

```powershell
& "C:\Programming_Files\Godot\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" --headless --path . --scene res://tests/pack_rat_component_smoke.tscn
& "C:\Programming_Files\Godot\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" --headless --path . --scene res://tests/pack_rat_http_zip_smoke.tscn
& "C:\Programming_Files\Godot\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" --headless --path . --scene res://tests/pack_rat_http_pck_smoke.tscn
& "C:\Programming_Files\Godot\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" --headless --path . --scene res://tests/pack_rat_pck_hot_update_probe.tscn
git diff --check
rg -n "preload\(" addons\pack_rat -S
```

## VirtuCade Coverage Reminder

PackRat should stay generic. VirtuCade and multi-server-test should implement
world-specific logic on top of PackRat, not inside PackRat.

Expected integration shape:

```gdscript
rpc_id(peer_id, "prepare_world_transfer", world_id, expected_modified_time, expected_size)
```

Client-side project convention:

```gdscript
var url := PackRat.join_url(world_pack_base_url, "%s.pck" % world_id)
var options := PackRatOptions.from_expected_metadata(expected_modified_time, expected_size)
var result := await PackRat.load_resource_pack(url, options)
var scene_path := "res://server/worlds/%s/%s.tscn" % [world_id, world_id]
```

The game should verify the expected scene/resource exists after the pack loads.
PackRat may eventually grow a generic optional entry-path validation helper, but
it should not know about worlds, scenes, master servers, or transfer tickets.

## Final Instruction

This file is documentation only. Do not restructure the addon just because this
handoff exists. Challenge the structure again before implementation, then make a
small focused commit if the move is still worth it.
