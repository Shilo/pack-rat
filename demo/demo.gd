class_name PackRatDemo extends Control
## PackRat Portal: a polished WebGL-friendly runtime DLC showcase.

const _SOURCE_ARG: String = "--source="
const _PACK_BASE_ARG: String = "--pack-base-url="
const _RELEASE_TAG_ARG: String = "--release-tag="
const _AUTO_LOAD_ARG: String = "--auto-load="

var _source: String = PackRatDemoCatalog.SOURCE_PAGES
var _pack_base_arg_applied: bool = false
var _cards: Array[PackRatDemoCard] = []
var _selected_result: PackRatResult
var _quit_when_done: bool = false
var _auto_load_ids: PackedStringArray = []
var _pending_auto_loads: int = 0
var _auto_load_failed: bool = false

@onready var _source_selector: OptionButton = %SourceSelector
@onready var _mounted_scene_host: Control = %MountedSceneHost
@onready var _preview_placeholder: Control = %PreviewPlaceholder
@onready var _preview_title: Label = %PreviewTitle
@onready var _preview_status: Label = %PreviewStatus
@onready var _open_full_scene_button: Button = %OpenFullSceneButton
@onready var _warehouse_card: PackRatDemoCard = %WarehouseCard
@onready var _gallery_card: PackRatDemoCard = %GalleryCard


func _ready() -> void:
	_apply_user_args()
	_cards = [_warehouse_card, _gallery_card]
	_source_selector.select(1 if _source == PackRatDemoCatalog.SOURCE_GITHUB_RELEASE else 0)
	_source_selector.item_selected.connect(_on_source_selected)
	_open_full_scene_button.pressed.connect(_on_open_full_scene_pressed)
	%ClearAllButton.pressed.connect(_on_clear_all_pressed)

	for card in _cards:
		card.set_source(_source)
		card.preview_requested.connect(_on_preview_requested)
		card.load_finished.connect(_on_load_finished)

	_show_placeholder()
	_start_auto_loads()


func _show_placeholder() -> void:
	_clear_preview()
	_preview_placeholder.visible = true
	_preview_status.text = "Load a pack to mount a scene here."
	_open_full_scene_button.disabled = true


func _on_source_selected(index: int) -> void:
	_source = PackRatDemoCatalog.SOURCE_GITHUB_RELEASE if index == 1 else PackRatDemoCatalog.SOURCE_PAGES
	for card in _cards:
		card.set_source(_source)


func _on_preview_requested(pack: PackRatDemoPack, result: PackRatResult) -> void:
	var scene: PackedScene = result.load_entry_scene()
	if scene == null:
		_preview_status.text = "Entry scene was not found after mount."
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


func _on_open_full_scene_pressed() -> void:
	if _selected_result == null:
		return

	var error: Error = _selected_result.change_scene_to_entry(get_tree())
	if error != OK:
		_preview_status.text = "Could not open full scene (error %d)." % error


func _on_clear_all_pressed() -> void:
	var options: PackRatOptions = PackRatOptions.new()
	options.cache_dir = PackRatDemoCatalog.cache_dir
	var error: Error = PackRat.clear_cache(options)
	if error == OK:
		_preview_status.text = "Disk cache cleared. Mounted rooms persist until reload."
	else:
		_preview_status.text = "Could not clear disk cache (error %d)." % error


func _on_load_finished(_pack: PackRatDemoPack, result: PackRatResult) -> void:
	if _pending_auto_loads <= 0:
		return

	_pending_auto_loads -= 1
	if not result.ok:
		_auto_load_failed = true

	if _pending_auto_loads == 0 and _quit_when_done:
		get_tree().quit(1 if _auto_load_failed else 0)


func _clear_preview() -> void:
	for child in _mounted_scene_host.get_children():
		child.queue_free()


func _start_auto_loads() -> void:
	if _auto_load_ids.is_empty():
		if _quit_when_done:
			get_tree().quit()
		return

	for card in _cards:
		var pack: PackRatDemoPack = card.pack()
		if pack != null and _auto_load_ids.has(pack.id):
			_pending_auto_loads += 1
			card.load_pack()

	if _pending_auto_loads == 0 and _quit_when_done:
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
