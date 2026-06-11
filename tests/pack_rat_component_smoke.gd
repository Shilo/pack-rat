extends Node

const PACKRAT_SCRIPTS: Array[Script] = [
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

	print("PackRat component smoke passed.")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
