extends Node

const PACKRAT_SCRIPTS: Array[Script] = [
	preload("res://addons/pack_rat/pack_rat.gd"),
	preload("res://addons/pack_rat/cache/pack_rat_cache.gd"),
	preload("res://addons/pack_rat/cache/pack_rat_cache_files.gd"),
	preload("res://addons/pack_rat/cache/pack_rat_cache_paths.gd"),
	preload("res://addons/pack_rat/cache/pack_rat_cache_record.gd"),
	preload("res://addons/pack_rat/core/pack_rat_options.gd"),
	preload("res://addons/pack_rat/core/pack_rat_request.gd"),
	preload("res://addons/pack_rat/core/pack_rat_result.gd"),
	preload("res://addons/pack_rat/filesystem/pack_rat_file_metadata.gd"),
	preload("res://addons/pack_rat/request/pack_rat_http_client.gd"),
	preload("res://addons/pack_rat/request/pack_rat_http_response.gd"),
	preload("res://addons/pack_rat/request/pack_rat_request_runner.gd"),
	preload("res://addons/pack_rat/request/pack_rat_web_fetch_client.gd"),
	preload("res://addons/pack_rat/resource_pack/pack_rat_loader.gd"),
	preload("res://addons/pack_rat/resource_pack/pack_rat_mount_registry.gd"),
]


func _ready() -> void:
	if PACKRAT_SCRIPTS.is_empty():
		_fail("PackRat scripts were not preloaded.")
		return

	var options: PackRatOptions = PackRatOptions.new()
	options.id = "Hub Pack"
	options.entry_path = "res://dlc/hub/main.tscn"
	if options.download_chunk_size != 4 * 1024 * 1024:
		_fail("Expected PackRatOptions to default to a large resource-pack download chunk.")
		return

	if options.capture_timings:
		_fail("Expected PackRatOptions to disable capture_timings by default.")
		return

	if not options.use_web_fetch:
		_fail("Expected PackRatOptions to enable browser fetch by default when available.")
		return

	if not options.accept_gzip:
		_fail("Expected PackRatOptions to accept gzip transfer compression by default.")
		return

	if options.use_threads:
		_fail("Expected PackRatOptions to leave native HTTPRequest threads opt-in.")
		return

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

	var expected_options: PackRatOptions = PackRatOptions.from_expected_metadata(metadata.modified_time, metadata.size)
	if expected_options.expected_modified_time != metadata.modified_time:
		_fail("Expected from_expected_metadata to copy modified time.")
		return

	if expected_options.expected_size != metadata.size:
		_fail("Expected from_expected_metadata to copy size.")
		return

	metadata_options.request_headers.append("X-PackRat-Test: one")
	metadata_options.download_chunk_size = 2 * 1024 * 1024
	metadata_options.capture_timings = true
	metadata_options.use_web_fetch = false
	metadata_options.accept_gzip = false
	metadata_options.progress_total_size = 2048
	metadata_options.use_threads = false
	var copied_options: PackRatOptions = metadata_options.copy()
	metadata_options.cache_dir = "user://changed_after_copy"
	metadata_options.request_headers.append("X-PackRat-Test: two")
	metadata_options.download_chunk_size = 1024
	metadata_options.capture_timings = false
	metadata_options.use_web_fetch = true
	metadata_options.accept_gzip = true
	metadata_options.progress_total_size = 4096
	metadata_options.use_threads = true
	if copied_options.cache_dir == metadata_options.cache_dir:
		_fail("Expected PackRatOptions.copy to snapshot cache_dir.")
		return

	if copied_options.request_headers.size() != 1:
		_fail("Expected PackRatOptions.copy to duplicate request headers.")
		return

	if copied_options.download_chunk_size != 2 * 1024 * 1024:
		_fail("Expected PackRatOptions.copy to snapshot download_chunk_size.")
		return

	if not copied_options.capture_timings:
		_fail("Expected PackRatOptions.copy to snapshot capture_timings.")
		return

	if copied_options.use_web_fetch:
		_fail("Expected PackRatOptions.copy to snapshot use_web_fetch.")
		return

	if copied_options.accept_gzip:
		_fail("Expected PackRatOptions.copy to snapshot accept_gzip.")
		return

	if copied_options.progress_total_size != 2048:
		_fail("Expected PackRatOptions.copy to snapshot progress_total_size.")
		return

	if copied_options.use_threads:
		_fail("Expected PackRatOptions.copy to snapshot use_threads.")
		return

	var gzip_response: PackRatHttpResponse = PackRatHttpResponse.from_completed(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray([
			"Content-Encoding: gzip",
			"Content-Length: 123",
			"Content-Type: application/octet-stream",
		])
	)
	if gzip_response.content_length != 0:
		_fail("Expected gzip Content-Length to be transfer-only metadata.")
		return

	if gzip_response.transfer_content_length != 123:
		_fail("Expected gzip response to preserve transfer Content-Length.")
		return

	var joined_url: String = PackRat.join_url("https://cdn.example.com/worlds/", "/hub.pck")
	if joined_url != "https://cdn.example.com/worlds/hub.pck":
		_fail("Expected join_url to build a clean URL.")
		return

	var metadata_dict: Dictionary = metadata.to_dictionary()
	if int(metadata_dict.get("size", 0)) != metadata.size:
		_fail("Expected file_metadata dictionary to include size.")
		return

	var missing_metadata: PackRatFileMetadata = PackRat.file_metadata("user://pack_rat_missing_metadata_smoke.bin")
	if missing_metadata.ok or missing_metadata.error.is_empty():
		_fail("Expected missing file_metadata to fail with an error.")
		return

	var scene_result: PackRatResult = PackRatResult.new()
	scene_result.ok = true
	scene_result.entry_path = "res://tests/pack_rat_component_smoke.tscn"
	if not scene_result.entry_scene_exists():
		_fail("Expected entry_scene_exists to find the component smoke scene.")
		return

	if scene_result.load_entry_scene() == null:
		_fail("Expected load_entry_scene to load the component smoke scene.")
		return

	scene_result.entry_path = "res://tests/missing_pack_rat_scene.tscn"
	if scene_result.entry_scene_exists():
		_fail("Expected entry_scene_exists to reject a missing scene.")
		return

	if scene_result.change_scene_to_entry() != ERR_FILE_NOT_FOUND:
		_fail("Expected change_scene_to_entry to reject a missing scene.")
		return

	var unsafe_clear_options: PackRatOptions = PackRatOptions.new()
	unsafe_clear_options.cache_dir = "user://"
	if PackRat.clear_cache(unsafe_clear_options) != ERR_INVALID_PARAMETER:
		_fail("Expected clear_cache to reject root user:// cache dir.")
		return

	unsafe_clear_options.cache_dir = "user://pack_rat/../outside"
	if PackRat.clear_cache(unsafe_clear_options) != ERR_INVALID_PARAMETER:
		_fail("Expected clear_cache to reject parent directory segments.")
		return

	var unsafe_load_options: PackRatOptions = PackRatOptions.new()
	unsafe_load_options.cache_dir = "user://pack_rat/../outside"
	var unsafe_load: PackRatResult = await PackRat.load_resource_pack("https://example.com/hub.pck", unsafe_load_options)
	if unsafe_load.ok or not unsafe_load.error.contains("cache_dir"):
		_fail("Expected load_resource_pack to reject unsafe cache_dir.")
		return

	print("PackRat component smoke passed.")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
