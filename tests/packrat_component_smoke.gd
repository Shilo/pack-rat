extends Node

const PACKRAT_SCRIPTS := [
	preload("res://addons/packrat/pack_rat.gd"),
	preload("res://addons/packrat/pack_rat_service.gd"),
	preload("res://addons/packrat/pack_rat_options.gd"),
	preload("res://addons/packrat/pack_rat_result.gd"),
	preload("res://addons/packrat/pack_rat_descriptor.gd"),
	preload("res://addons/packrat/pack_rat_operation.gd"),
	preload("res://addons/packrat/cache/pack_rat_cache_store.gd"),
	preload("res://addons/packrat/cache/pack_rat_json_cache_store.gd"),
	preload("res://addons/packrat/freshness/pack_rat_freshness_checker.gd"),
	preload("res://addons/packrat/freshness/pack_rat_freshness_decision.gd"),
	preload("res://addons/packrat/freshness/pack_rat_http_freshness_checker.gd"),
	preload("res://addons/packrat/http/pack_rat_http_client.gd"),
	preload("res://addons/packrat/http/pack_rat_http_response.gd"),
	preload("res://addons/packrat/installers/pack_rat_file_installer.gd"),
	preload("res://addons/packrat/installers/pack_rat_installer.gd"),
	preload("res://addons/packrat/installers/pack_rat_resource_pack_installer.gd"),
	preload("res://addons/packrat/sources/pack_rat_http_source_resolver.gd"),
	preload("res://addons/packrat/sources/pack_rat_source_resolver.gd"),
	preload("res://addons/packrat/validation/pack_rat_basic_validator.gd"),
	preload("res://addons/packrat/validation/pack_rat_sha256_validator.gd"),
	preload("res://addons/packrat/validation/pack_rat_validation_result.gd"),
	preload("res://addons/packrat/validation/pack_rat_validator.gd"),
]


func _ready() -> void:
	if PACKRAT_SCRIPTS.is_empty():
		_fail("PackRat scripts were not preloaded.")
		return

	var options := PackRatOptions.new()
	options.id = "Hub Pack"
	options.entry_path = "res://dlc/hub/main.tscn"

	var descriptor := PackRatDescriptor.from_url("https://example.com/packs/hub.pck?token=demo", options)
	if not descriptor.ok:
		_fail(descriptor.error)
		return

	if descriptor.id != "hub_pack":
		_fail("Expected sanitized id hub_pack, got %s." % descriptor.id)
		return

	if descriptor.install_mode != PackRatOptions.InstallMode.RESOURCE_PACK:
		_fail("Expected .pck URL to infer resource-pack install mode.")
		return

	var failed := PackRatResult.failed("intentional")
	if failed.ok or failed.status != PackRatResult.STATUS_FAILED:
		_fail("PackRatResult.failed() did not produce a failed result.")
		return

	print("PackRat component smoke passed.")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
