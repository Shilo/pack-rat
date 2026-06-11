class_name PackRatDemoCatalog extends RefCounted
## Static catalog for the PackRat Portal demo.

## Same-origin static-host source used by the WebGL demo.
const SOURCE_PAGES: String = "pages"

## GitHub Release source, mainly for native/editor testing.
const SOURCE_GITHUB_RELEASE: String = "github_release"

## Repository owner for canonical GitHub Release assets.
const RELEASE_OWNER: String = "Shilo"

## Repository name for canonical GitHub Release assets.
const RELEASE_REPO: String = "pack-rat"

## Warehouse PCK release asset filename.
const WAREHOUSE_FILE_NAME: String = "packrat-demo-warehouse.pck"

## Gallery ZIP release asset filename.
const GALLERY_FILE_NAME: String = "packrat-demo-gallery.zip"

## Warehouse PCK entry scene.
const WAREHOUSE_ENTRY_PATH: String = "res://packrat_demo/warehouse/main.tscn"

## Gallery ZIP entry scene.
const GALLERY_ENTRY_PATH: String = "res://packrat_demo/gallery/main.tscn"

## Generated expected byte size for the warehouse PCK.
const WAREHOUSE_EXPECTED_SIZE: int = 10495564

## Generated expected byte size for the gallery ZIP.
const GALLERY_EXPECTED_SIZE: int = 16791372

## Generated expected modified time for the warehouse PCK, when available.
const WAREHOUSE_EXPECTED_MODIFIED_TIME: int = 0

## Generated expected modified time for the gallery ZIP, when available.
const GALLERY_EXPECTED_MODIFIED_TIME: int = 0

## Canonical Pages pack mirror used outside Web exports.
static var pages_pack_base_url: String = "https://shilo.github.io/pack-rat/packs"

## Release tag used by [method PackRat.github_release_url].
static var release_tag: String = "latest"

## Cache directory used by the demo cards.
static var cache_dir: String = "user://pack_rat_demo"


## Uses the current browser page as the static pack host when running on Web.
static func use_web_same_origin_pack_base() -> void:
	if not Engine.has_singleton("JavaScriptBridge"):
		return

	var javascript: Object = Engine.get_singleton("JavaScriptBridge")
	if javascript == null:
		return

	var value: Variant = javascript.call("eval", "new URL('packs', window.location.href).href", true)
	if typeof(value) == TYPE_STRING and not String(value).is_empty():
		pages_pack_base_url = String(value).trim_suffix("/")


## Returns the hardcoded showcase packs.
static func packs() -> Array[PackRatDemoPack]:
	var result: Array[PackRatDemoPack] = []
	result.append(PackRatDemoPack.create(
		"warehouse",
		"Warehouse PCK",
		"A playful box-room packed as Godot's native resource-pack format.",
		"PCK",
		WAREHOUSE_FILE_NAME,
		WAREHOUSE_ENTRY_PATH,
		WAREHOUSE_EXPECTED_SIZE,
		WAREHOUSE_EXPECTED_MODIFIED_TIME,
		Color.html("#8A5729")
	))
	result.append(PackRatDemoPack.create(
		"gallery",
		"Gallery ZIP",
		"A content-heavy app page packed as a standard ZIP resource pack.",
		"ZIP",
		GALLERY_FILE_NAME,
		GALLERY_ENTRY_PATH,
		GALLERY_EXPECTED_SIZE,
		GALLERY_EXPECTED_MODIFIED_TIME,
		Color.html("#27806C")
	))
	return result


## Returns the pack with [param id], or [code]null[/code] when it is unknown.
static func pack_by_id(id: String) -> PackRatDemoPack:
	for pack in packs():
		if pack.id == id:
			return pack

	return null


## Returns a compact label for [param source].
static func source_label(source: String) -> String:
	if source == SOURCE_GITHUB_RELEASE:
		return "GitHub Release"

	return "GitHub Pages"
