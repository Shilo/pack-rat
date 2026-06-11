extends Node

@export var pack_url: String = ""
@export var local_pack_path: String = ""
@export var pack_id: String = ""
@export var entry_path: String = ""
@export var expected_size: int = 0
@export var expected_modified_time: int = 0
@export var offline_first: bool = false
@export var quit_when_done: bool = false


func _ready() -> void:
	_apply_user_args()

	var options: PackRatOptions = PackRatOptions.new()
	options.id = pack_id
	options.entry_path = entry_path
	options.expected_size = expected_size
	options.expected_modified_time = expected_modified_time
	options.offline_first = offline_first

	if not local_pack_path.is_empty():
		var metadata: PackRatFileMetadata = PackRat.file_metadata(local_pack_path)
		if not metadata.ok:
			push_error("PackRat demo: %s" % metadata.error)
			if quit_when_done:
				get_tree().quit(1)
			return

		metadata.apply_to_options(options)
		print("PackRat demo metadata: %s" % JSON.stringify(metadata.to_dictionary()))

	if pack_url.is_empty():
		print("PackRat demo: pass --pack-url=https://example.com/packs/hub.pck to load a remote pack.")
		if quit_when_done:
			get_tree().quit()
		return

	var request: PackRatRequest = PackRat.load_resource_pack_async(pack_url, options)
	request.progress_changed.connect(_on_progress_changed)
	await request.completed
	var result: PackRatResult = request.result
	print(JSON.stringify(result.to_dictionary(), "\t"))

	if quit_when_done:
		get_tree().quit(0 if result.ok else 1)


func _apply_user_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pack-url="):
			pack_url = argument.substr("--pack-url=".length())
		elif argument.begins_with("--local-pack-path="):
			local_pack_path = argument.substr("--local-pack-path=".length())
		elif argument.begins_with("--id="):
			pack_id = argument.substr("--id=".length())
		elif argument.begins_with("--entry-path="):
			entry_path = argument.substr("--entry-path=".length())
		elif argument.begins_with("--expected-size="):
			expected_size = int(argument.substr("--expected-size=".length()))
		elif argument.begins_with("--expected-modified-time="):
			expected_modified_time = int(argument.substr("--expected-modified-time=".length()))
		elif argument == "--offline-first":
			offline_first = true


func _on_progress_changed(downloaded_bytes: int, total_bytes: int) -> void:
	if total_bytes > 0:
		print("PackRat demo: downloaded %d / %d bytes" % [downloaded_bytes, total_bytes])
	else:
		print("PackRat demo: downloaded %d bytes" % downloaded_bytes)
