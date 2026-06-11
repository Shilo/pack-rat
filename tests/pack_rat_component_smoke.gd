extends Node

const PACKRAT_SCRIPTS: Array[Script] = [
	preload("res://addons/pack_rat/pack_rat_file_metadata.gd"),
	preload("res://addons/pack_rat/pack_rat.gd"),
	preload("res://addons/pack_rat/pack_rat_options.gd"),
	preload("res://addons/pack_rat/pack_rat_result.gd"),
	preload("res://addons/pack_rat/internal/pack_rat_cache.gd"),
	preload("res://addons/pack_rat/internal/pack_rat_cache_record.gd"),
	preload("res://addons/pack_rat/internal/pack_rat_http_response.gd"),
	preload("res://addons/pack_rat/internal/pack_rat_request_runner.gd"),
	preload("res://addons/pack_rat/pack_rat_request.gd"),
]


func _ready() -> void:
	if PACKRAT_SCRIPTS.is_empty():
		_fail("PackRat scripts were not preloaded.")
		return

	var options: PackRatOptions = PackRatOptions.new()
	options.id = "Hub Pack"
	options.entry_path = "res://dlc/hub/main.tscn"

	var invalid: PackRatResult = await PackRat.load_resource_pack("not-a-url", options)
	if invalid.ok or invalid.status != PackRatResult.STATUS_FAILED:
		_fail("Expected invalid URL to return a failed result.")
		return

	var metadata_path: String = "user://pack_rat_metadata_component_smoke.bin"
	var file: FileAccess = FileAccess.open(metadata_path, FileAccess.WRITE)
	if file == null:
		_fail("Could not create metadata smoke file.")
		return

	file.store_buffer("packrat".to_utf8_buffer())
	file = null

	var metadata: PackRatFileMetadata = PackRat.file_metadata(metadata_path)
	if not metadata.ok:
		_fail("Expected file_metadata to succeed: %s" % metadata.error)
		return

	if metadata.size != 7:
		_fail("Expected file_metadata size 7, got %d." % metadata.size)
		return

	if metadata.modified_time <= 0:
		_fail("Expected file_metadata modified_time to be positive.")
		return

	var metadata_options: PackRatOptions = PackRatOptions.new()
	metadata.apply_to_options(metadata_options)
	if metadata_options.expected_size != metadata.size:
		_fail("Expected metadata.apply_to_options to copy size.")
		return

	if metadata_options.expected_modified_time != metadata.modified_time:
		_fail("Expected metadata.apply_to_options to copy modified time.")
		return

	var metadata_dict: Dictionary = metadata.to_dictionary()
	if int(metadata_dict.get("size", 0)) != metadata.size:
		_fail("Expected file_metadata dictionary to include size.")
		return

	var missing_metadata: PackRatFileMetadata = PackRat.file_metadata("user://pack_rat_missing_metadata_smoke.bin")
	if missing_metadata.ok or missing_metadata.error.is_empty():
		_fail("Expected missing file_metadata to fail with an error.")
		return

	var unsafe_clear_options: PackRatOptions = PackRatOptions.new()
	unsafe_clear_options.cache_dir = "user://"
	if PackRat.clear_cache(unsafe_clear_options) != ERR_INVALID_PARAMETER:
		_fail("Expected clear_cache to reject root user:// cache dir.")
		return

	print("PackRat component smoke passed.")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
