extends Node

@export var pack_url: String = ""
@export var entry_path: String = ""
@export var quit_when_done: bool = false


func _ready() -> void:
	_apply_user_args()

	if pack_url.is_empty():
		print("PackRat demo: pass --pack-url=https://example.com/packs/hub.pck to try the runtime path.")
		if quit_when_done:
			get_tree().quit()
		return

	var options: PackRatOptions = PackRatOptions.new()
	options.entry_path = entry_path

	var result: PackRatResult = await PackRat.prepare(pack_url, options)
	print(JSON.stringify(result.to_dictionary(), "\t"))

	if quit_when_done:
		get_tree().quit(0 if result.ok else 1)


func _apply_user_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pack-url="):
			pack_url = argument.substr("--pack-url=".length())
		elif argument.begins_with("--entry-path="):
			entry_path = argument.substr("--entry-path=".length())
