class_name PackRatDemo extends Control
## PackRat Portal: a polished WebGL-friendly runtime DLC showcase.

const _SOURCE_ARG: String = "--source="
const _PACK_BASE_ARG: String = "--pack-base-url="
const _RELEASE_TAG_ARG: String = "--release-tag="
const _AUTO_LOAD_ARG: String = "--auto-load="
const _NARROW_WIDTH: float = 900.0

var _source: String = PackRatDemoCatalog.SOURCE_PAGES
var _pack_base_arg_applied: bool = false
var _cards: Array[PackRatDemoCard] = []
var _selected_result: PackRatResult
var _quit_when_done: bool = false
var _auto_load_ids: PackedStringArray = []
var _pending_auto_loads: int = 0
var _auto_load_failed: bool = false

@onready var _page: MarginContainer = %Page
@onready var _header: BoxContainer = %Header
@onready var _body: BoxContainer = %Body
@onready var _cards_panel: PanelContainer = %CardsPanel
@onready var _source_selector: OptionButton = %SourceSelector
@onready var _mounted_scene_host: Control = %MountedSceneHost
@onready var _preview_placeholder: Control = %PreviewPlaceholder
@onready var _preview_title: Label = %PreviewTitle
@onready var _preview_status: Label = %PreviewStatus
@onready var _open_full_scene_button: Button = %OpenFullSceneButton
@onready var _preview_host: Control = %PreviewHost
@onready var _toast_panel: PanelContainer = %ToastPanel
@onready var _toast_label: Label = %ToastLabel
@onready var _warehouse_card: PackRatDemoCard = %WarehouseCard
@onready var _gallery_card: PackRatDemoCard = %GalleryCard


func _ready() -> void:
	_apply_user_args()
	_apply_web_source_limits()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_cards = [_warehouse_card, _gallery_card]
	_source_selector.select(1 if _source == PackRatDemoCatalog.SOURCE_GITHUB_RELEASE else 0)
	_source_selector.item_selected.connect(_on_source_selected)
	_open_full_scene_button.pressed.connect(_on_open_full_scene_pressed)
	%ClearAllButton.pressed.connect(_on_clear_all_pressed)

	for card in _cards:
		card.set_source(_source)
		card.preview_requested.connect(_on_preview_requested)
		card.load_finished.connect(_on_load_finished)
		card.message_requested.connect(_show_toast)

	_apply_responsive_layout()
	_show_placeholder()
	_show_toast("Ready")
	_start_auto_loads()


func _show_placeholder() -> void:
	_clear_preview()
	_preview_placeholder.visible = true
	_preview_status.text = "Load a pack to mount a scene here."
	_open_full_scene_button.disabled = true


func _apply_responsive_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var narrow: bool = viewport_size.x < _NARROW_WIDTH or viewport_size.x < viewport_size.y
	_header.vertical = narrow
	_body.vertical = narrow

	var margin: int = 14 if narrow else 28
	_page.add_theme_constant_override("margin_left", margin)
	_page.add_theme_constant_override("margin_top", 14 if narrow else 24)
	_page.add_theme_constant_override("margin_right", margin)
	_page.add_theme_constant_override("margin_bottom", 14 if narrow else 24)

	_cards_panel.custom_minimum_size = Vector2(0.0 if narrow else 360.0, 0.0)
	_preview_host.custom_minimum_size = Vector2(0.0 if narrow else 420.0, 260.0 if narrow else 320.0)
	_toast_panel.custom_minimum_size = Vector2(0.0 if narrow else 184.0, 42.0 if narrow else 48.0)


func _show_toast(message: String, is_error: bool = false) -> void:
	if message.is_empty():
		return

	_toast_label.text = message
	if is_error:
		_toast_label.add_theme_color_override("font_color", Color.html("#FFECE6"))
		printerr("PackRat demo error: %s" % message)
	else:
		_toast_label.add_theme_color_override("font_color", Color.html("#F6ECD9"))
		print("PackRat demo: %s" % message)


func _on_source_selected(index: int) -> void:
	if index == 1 and _github_release_blocked_in_browser():
		_source_selector.select(0)
		_source = PackRatDemoCatalog.SOURCE_PAGES
		_show_toast("GitHub Release assets are blocked by browser CORS; using GitHub Pages.", true)
		return

	_source = PackRatDemoCatalog.SOURCE_GITHUB_RELEASE if index == 1 else PackRatDemoCatalog.SOURCE_PAGES
	for card in _cards:
		card.set_source(_source)
	_show_toast("Source set to %s." % PackRatDemoCatalog.source_label(_source))


func _on_preview_requested(pack: PackRatDemoPack, result: PackRatResult) -> void:
	var scene: PackedScene = result.load_entry_scene()
	if scene == null:
		_preview_status.text = "Entry scene was not found after mount."
		_show_toast("Entry scene was not found after mount.", true)
		return

	_clear_preview()
	_preview_placeholder.visible = false
	var instance: Node = scene.instantiate()
	_mounted_scene_host.add_child(instance)
	if instance is Control:
		var control: Control = instance
		control.set_anchors_preset(Control.PRESET_FULL_RECT)

	_selected_result = result
	_preview_title.text = pack.title
	_preview_status.text = "%s from %s" % [result.status, "cache" if result.from_cache else "remote"]
	_open_full_scene_button.disabled = false
	_show_toast("Previewing %s." % pack.title)


func _on_open_full_scene_pressed() -> void:
	if _selected_result == null:
		return

	var error: Error = _selected_result.change_scene_to_entry(get_tree())
	if error != OK:
		_preview_status.text = "Could not open full scene (error %d)." % error
		_show_toast("Could not open full scene (error %d)." % error, true)


func _on_clear_all_pressed() -> void:
	var options: PackRatOptions = PackRatOptions.new()
	options.cache_dir = PackRatDemoCatalog.cache_dir
	var error: Error = PackRat.clear_cache(options)
	if error == OK:
		_preview_status.text = "Disk cache cleared. Mounted rooms persist until reload."
		_show_toast("Disk cache cleared.")
	else:
		_preview_status.text = "Could not clear disk cache (error %d)." % error
		_show_toast("Could not clear disk cache (error %d)." % error, true)


func _on_load_finished(_pack: PackRatDemoPack, result: PackRatResult) -> void:
	if _pending_auto_loads <= 0:
		return

	_pending_auto_loads -= 1
	if not result.ok:
		_auto_load_failed = true

	if _pending_auto_loads == 0 and _quit_when_done:
		if _auto_load_failed:
			_show_toast("Auto-load finished with errors.", true)
		else:
			_show_toast("Auto-load finished.")
		get_tree().quit(1 if _auto_load_failed else 0)


func _clear_preview() -> void:
	for child in _mounted_scene_host.get_children():
		child.queue_free()


func _start_auto_loads() -> void:
	if _auto_load_ids.is_empty():
		if _quit_when_done:
			_show_toast("No auto-load packs requested.")
			get_tree().quit()
		return

	for card in _cards:
		var pack: PackRatDemoPack = card.pack()
		if pack != null and _auto_load_ids.has(pack.id):
			_pending_auto_loads += 1
			card.load_pack()

	if _pending_auto_loads == 0 and _quit_when_done:
		_show_toast("No matching auto-load packs were found.", true)
		get_tree().quit(1)


func _apply_user_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(_SOURCE_ARG):
			var source: String = argument.substr(_SOURCE_ARG.length())
			if source == PackRatDemoCatalog.SOURCE_GITHUB_RELEASE or source == PackRatDemoCatalog.SOURCE_PAGES:
				_source = source
		elif argument.begins_with(_PACK_BASE_ARG):
			_pack_base_arg_applied = true
			PackRatDemoCatalog.pages_pack_base_url = argument.substr(_PACK_BASE_ARG.length())
		elif argument.begins_with(_RELEASE_TAG_ARG):
			PackRatDemoCatalog.release_tag = argument.substr(_RELEASE_TAG_ARG.length())
		elif argument.begins_with(_AUTO_LOAD_ARG):
			_auto_load_ids = argument.substr(_AUTO_LOAD_ARG.length()).split(",", false)
		elif argument == "--quit-when-done":
			_quit_when_done = true

	if not _pack_base_arg_applied:
		PackRatDemoCatalog.use_web_same_origin_pack_base()


func _apply_web_source_limits() -> void:
	if not _github_release_blocked_in_browser():
		return

	if _source == PackRatDemoCatalog.SOURCE_GITHUB_RELEASE:
		_source = PackRatDemoCatalog.SOURCE_PAGES

	_source_selector.set_item_disabled(1, true)
	_source_selector.set_item_text(1, "GitHub Release asset (native only)")


func _github_release_blocked_in_browser() -> bool:
	return OS.has_feature("web")
