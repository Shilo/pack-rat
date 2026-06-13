# PackRat — Godot Deep Review (review only)

> **This is a read-only review. No source code was changed.** Every item below
> is a finding or recommendation, not an applied edit. The four addon files
> touched during an earlier exploratory pass were reverted; `git status` shows
> only this document.

- **Project:** PackRat — a runtime DLC/content-pack downloader, verifier,
  cacher, and mounter delivered as a script-only Godot addon.
- **Engine:** Godot **4.6.3.stable** (`config/features=("4.6", "GL Compatibility")`).
- **Review date:** 2026-06-12
- **Scope read:** `addons/pack_rat/` (15 scripts), `demo/` (6), `tools/` (1),
  `tests/` (7), `README.md`, `export_presets.cfg`, `.github/workflows/demo.yml`,
  `project.godot`, `.mcp.json`.
- **Headline:** Mature, well-architected, thoroughly tested. No bugs, no
  obsolete compatibility code, and no dead code found. A handful of low-priority
  quality opportunities (dedup / cleanup / consistency) are catalogued in §5–§9
  with concrete locations and a priority table in §12.

---

## 1. Method

1. Full read of all 29 scripts + configs.
2. Searched for `TODO/FIXME/HACK`, `deprecated/legacy/compat`, Godot-3 patterns,
   and commented-out code.
3. Reference-counted **every** addon function across `.gd`/`.tscn` to find dead
   symbols.
4. Line-by-line re-read of the loader, atomic cache save, cache-clear matching,
   mount registry, and the web `fetch()` bridge.
5. Quality pass for each requested dimension: performance, simplification,
   deduplication, abstraction, cleanup.
6. Ran the four hermetic smoke suites under Godot 4.6.3 to confirm the project
   is green (§11).

---

## 2. Backwards-compatibility audit (primary mandate)

**Nothing to remove.** Godot-4.6-only project with zero obsolete-compat baggage:
no Godot 3 code paths, deprecated aliases, version shims, old save-format
migrations, stale feature flags, or commented-out implementations. The only
`LEGACY_*` token is a deliberate 64 KiB benchmark constant in
`tests/pack_rat_performance_smoke.gd` — a comparison baseline, not compat code.

---

## 3. Bug audit

No defects found. Verified correct (each is covered by the smoke suite):

| Area | Why correct |
| --- | --- |
| Loader parallel-download collision (`pack_rat_loader.gd:149-177`) | Mounts an already-present sibling download and discards its own `.part`; evicts + redownloads if that file fails to mount. |
| Atomic `cache.json` save (`pack_rat_cache.gd:68-108`) | `.tmp` write → `.bak` of old → rename, with restore-from-backup on failure; dirty-key sets cleared only on success. |
| `clear_cached_resource_pack` (`pack_rat.gd:102-163`) | Matches by URL/ID/filename/path, sweeps sibling versions, forgets fast cache; `cache.keys()` returns a copy so erase-during-iteration is safe. |
| Path safety (`pack_rat_cache_paths.gd`) | Rejects root/non-`user://`/`..` on both raw and normalized forms before `simplify_path()` could collapse a `..`. |
| Mount-registry cache-hit skip (`pack_rat_mount_registry.gd:18-24`) | Re-mount skipped only when the same id+signature is already mounted. |
| Async runner lifecycle (`pack_rat_request_runner.gd`) | Self-frees after completion **and** cancellation (smokes assert zero leaked runners). |
| Web `fetch()` file handle (`pack_rat_web_fetch_client.gd:423-427`) | Drops the only `FileAccess` ref; Godot 4 flushes/closes on unref. |

---

## 4. Dead-code audit

- Every addon function has ≥1 live call site (reference-counted across
  `.gd`/`.tscn`). No orphaned helpers.
- Spot-checked module/exported constants (`PackRatDemoCatalog.use_threads`,
  `WAREHOUSE_*`, `RANDOM_PACK_PATH`, `EXPECTED_SPACE`, etc.) — all referenced.

---

## 5. Deduplication opportunities (recommendations — not applied)

1. **Response-timing helpers triplicated.** `_timing_start`, `_record_timing`,
   and `_finish_timing` are byte-identical in `pack_rat_http_client.gd` and
   `pack_rat_web_fetch_client.gd` (the loader has a result-typed sibling set).
   *Recommendation:* hoist the start/record helpers to a shared home — natural
   fit is static methods on `PackRatHttpResponse`, which already owns
   `timings_msec` — and update call sites. *Caveat:* ~30 call sites across two
   files, one of which is the browser `fetch()` path that cannot be
   runtime-validated outside a Web export, so pair this refactor with a Web
   smoke run.

2. **Duplicated clamp magic numbers.** `clampi(options.download_chunk_size, 256,
   16 * 1024 * 1024)` appears verbatim in `pack_rat_http_client.gd:44` and
   `pack_rat_web_fetch_client.gd:232`, and `8 * 1024 * 1024` lives in a single
   private const with no named min/max. *Recommendation:* introduce named
   `MIN_/MAX_DOWNLOAD_CHUNK_SIZE` constants on `PackRatOptions` (the README
   already documents these as Godot's HTTPRequest limits) and reference them in
   both clients. Low risk; behavior-identical.

3. **Test harness duplication.** `_clear_directory`, `_make_directory`,
   `_has_part_files`, and a minimal `TCPServer` HTTP responder are reimplemented
   across `pack_rat_http_pck_smoke`, `pack_rat_http_zip_smoke`,
   `pack_rat_demo_smoke`, and `pack_rat_performance_smoke`. *Recommendation
   (optional):* extract a shared `res://tests/_support/` helper. *Trade-off:*
   broad multi-file change; the current self-contained smokes have real
   isolation value, so this is a judgment call, not a defect.

---

## 6. Simplification / consistency opportunities (recommendations — not applied)

1. **Loader inlines its own helper.** `pack_rat_loader.gd:13` and `:253` use
   `Time.get_ticks_msec() if capture_timings else 0` instead of the
   `_timing_start(capture_timings)` helper defined in the same file. Trivial
   consistency tidy.

2. **Native client lacks `_timing_start`.** `pack_rat_http_client.gd` inlines
   that expression ~7 times while the loader and web client have a helper. Best
   resolved together with the shared-helper consolidation in §5.1 rather than by
   adding a third local copy.

3. **Pack-extension knowledge in two places.** "pck or zip" is encoded both in
   `pack_rat_mount_registry.gd:12` and `PackRatCachePaths.is_cache_pack_file`.
   `mount_if_pack` could defer membership to `is_cache_pack_file` for a single
   source of truth. Marginal — it would couple mount logic to cache-path
   classification, so optional.

4. **Redundant prologue on the sync miss path.** `PackRat.load_resource_pack`
   copies/validates/derives/fast-cache-checks, then calls
   `load_resource_pack_async`, which repeats all of it. This is correct (the
   async entry must self-validate as public API) and cheap, but it is duplicated
   work. Only worth addressing with an internal prevalidated path if profiling
   ever shows it matters — currently it does not.

---

## 7. Performance analysis (the requested focus)

The download path is **already well-optimized**; the git history is a string of
deliberate perf passes and the README documents the rationale. No safe untapped
win was found. Confirmed-good behaviors:

- **Chunk sizing:** 8 MiB balanced default, clamped to Godot's 16 MiB max;
  64 KiB-vs-larger frame counts are regression-tested in `performance_smoke`
  (64 KiB → 165 progress frames vs 4 MiB → 7).
- **Once-per-frame native polling** is intentional — Godot's Web HTTP client
  cannot advance more than once per frame, which is exactly why the browser
  `fetch()` fast path exists (streams at native speed, chunks into Godot).
- **Progress dedup:** `PackRatRequest._set_progress` early-returns on unchanged
  `(downloaded,total)`, avoiding redundant signal emissions.
- **In-process fast cache:** `PackRatLoader.fast_cache_result` skips disk read
  and HTTP for repeated `expected_metadata`/`offline_first` hits — measured at
  50 cache hits in ~6–7 ms in the PCK smoke.
- **JS-side progress throttling** to ~2 FPS avoids JavaScriptBridge spam without
  slowing the actual browser download.

Observations (not optimizations to chase):

- `PackRatCache.load` parses the full `cache.json` per request, and `save()`
  re-reads it to merge concurrent writers. This is intentional concurrency
  safety; cost scales with cache-entry count, which is small for DLC caches.
- `PackRatCachePaths.safe_name` is char-by-char (`substr` + `to_lower` + linear
  membership test). Only runs during key derivation on short IDs — negligible.
- Cleanup directory scans (`clear_unmounted_cache_files`,
  `has_matching_cache_file`) are O(files) but run only on cache-clear, not in the
  hot path.

---

## 8. Abstraction assessment

Module boundaries are clean and proportionate: `core/` (options/request/result),
`cache/` (paths/files/record/index), `request/` (http/web-fetch/response/runner),
`resource_pack/` (loader/mount registry), `filesystem/` (metadata). No
god-objects, no leaky wrappers, no abstraction built for an abandoned design.
The static-facade `PackRat` over internal helpers is a sound, documented choice.
No change recommended.

---

## 9. Cleanup candidates (recommendations — not applied)

1. **Dead per-frame write.** `demo/packs/gallery/gallery_scene.gd:17` sets
   `card.rotation = 0.0` every `_process` though rotation is never set non-zero.
2. **Always-zero parameter.** `demo/packs/warehouse/warehouse_scene.gd`
   `_set_static_edge(... body_position ...)` is always called with
   `Vector2.ZERO`.

   *Important caveat for both:* these scripts are exported **inside** the demo
   packs (`demo/packs/*`). Editing the source has no runtime effect until the
   packs are re-exported, and re-exporting changes the committed pack bytes and
   forces a `tools/demo_pack_catalog.gd` size/token resync. So treat these as
   cosmetic notes to fold into the next intentional demo-pack rebuild, not
   standalone edits.

---

## 10. Intentional design choices verified (correct as-is)

- **No `addons/pack_rat/plugin.cfg`** — PackRat is a pure `class_name` library
  with no `EditorPlugin`/autoload; README states no plugin enable is needed.
- **Mounted packs persist for the process lifetime** — Godot exposes no per-pack
  unload; PackRat warns and keeps files rather than faking an unmount.
- **Web `fetch()` bridge `const total = 0`** — the browser stream has no reliable
  decoded length; totals come from `progress_total_size`/`expected_size`.
- **`accept_gzip` disabled on Web `HTTPRequest`** — avoids a double decode
  (browser already decodes the body); covered by the gzip transfer smoke.

---

## 11. Validation (baseline — confirms the project is green)

Ran headless with `Godot_v4.6.3-stable_win64` (matches `project.godot` and CI's
`GODOT_VERSION: 4.6.3`). Hermetic suites (no internet; loopback TCP / local PCK):

| Suite | Result |
| --- | --- |
| `pack_rat_component_smoke` | **PASS** |
| `pack_rat_pck_hot_update_probe` | **PASS** |
| `pack_rat_http_zip_smoke` | **PASS** (HEAD=2 GET=1) |
| `pack_rat_http_pck_smoke` | **PASS** (HEAD=3 GET=34; 50 cache hits ~6–7 ms) |

Not run locally (need exported packs / Web export): `pack_rat_demo_smoke`,
`pack_rat_performance_smoke`, `pack_rat_web_download_benchmark` — covered by CI.

---

## 12. Recommendation priority (all optional; nothing applied)

| Priority | Item | Effort | Risk | Locally validatable? |
| --- | --- | --- | --- | --- |
| Low | §5.2 named clamp constants | XS | Low | Native: yes (`performance_smoke` asserts the clamp). Web: compile-only. |
| Low | §6.1 loader uses `_timing_start` | XS | None | Yes |
| Low | §5.1 consolidate timing helpers | M | Low–Med | Native: yes; **Web path: needs a Web-export run** |
| Optional | §6.3 single pack-extension source | XS | Low | Yes (`http_pck`/`http_zip` smokes) |
| Optional | §5.3 shared test harness | M | Low | Yes (re-run smokes) |
| Cosmetic | §9 demo dead writes | XS | Low | Only via demo-pack re-export |

---

## 13. Conclusion

PackRat is in excellent, production-ready shape: fully typed GDScript, clean
module boundaries, structured error handling, opt-in profiling, careful atomic
cache writes, and an unusually thorough hermetic + CI test suite. This review
found **no bugs, no obsolete compatibility code, and no dead code**. The quality
opportunities above are minor and entirely optional; the highest-value one
(timing-helper deduplication, §5.1) should be paired with a Web-export smoke run
because it touches the browser `fetch()` path. Production-readiness claims here
are backed by the green hermetic suites in §11; the Web and exported-pack flows
remain CI-covered rather than verified in this local environment.
