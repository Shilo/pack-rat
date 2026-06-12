extends SceneTree
## Exports the editor-authored PackRat Portal demo DLC folders into PCK and ZIP packs.

## Default output directory for exported demo packs.
const DEFAULT_OUTPUT_DIR: String = "build/packs"

const _CATALOG_PATH: String = "res://demo/demo_catalog.gd"
const _OUTPUT_ARG: String = "--output-dir="
const _NO_CATALOG_ARG: String = "--no-catalog"


func _init() -> void:
	var output_dir: String = DEFAULT_OUTPUT_DIR
	var write_catalog: bool = true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(_OUTPUT_ARG):
			output_dir = argument.substr(_OUTPUT_ARG.length())
		elif argument == _NO_CATALOG_ARG:
			write_catalog = false

	var result: Dictionary = export_all(output_dir, write_catalog)
	if not bool(result.get("ok", false)):
		printerr(result.get("error", "Unknown demo pack export error."))
		quit(1)
		return

	print(JSON.stringify(result, "\t"))
	quit()


## Exports both editor-authored demo packs and optionally writes exported sizes into the catalog.
static func export_all(output_dir: String = DEFAULT_OUTPUT_DIR, write_catalog: bool = true) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"error": "",
		"warehouse_path": "",
		"gallery_path": "",
		"warehouse_size": 0,
		"gallery_size": 0,
	}

	var make_error: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		result.error = "Could not create output directory %s (error %d)." % [output_dir, make_error]
		return result

	var validate_error: String = _validate_sources()
	if not validate_error.is_empty():
		result.error = validate_error
		return result

	var warehouse_path: String = output_dir.path_join(PackRatDemoCatalog.WAREHOUSE_FILE_NAME)
	var gallery_path: String = output_dir.path_join(PackRatDemoCatalog.GALLERY_FILE_NAME)
	var warehouse_error: Error = _export_warehouse_pck(warehouse_path)
	if warehouse_error != OK:
		result.error = "Could not export warehouse PCK (error %d)." % warehouse_error
		return result

	var gallery_error: Error = _export_gallery_zip(gallery_path)
	if gallery_error != OK:
		result.error = "Could not export gallery ZIP (error %d)." % gallery_error
		return result

	var warehouse_size: int = FileAccess.get_size(warehouse_path)
	var gallery_size: int = FileAccess.get_size(gallery_path)
	if warehouse_size <= 0 or gallery_size <= 0:
		result.error = "Exported demo packs were empty."
		return result

	if write_catalog:
		var catalog_error: Error = _write_catalog_metadata(
			warehouse_size,
			gallery_size,
			_file_version_token(warehouse_path),
			_file_version_token(gallery_path)
		)
		if catalog_error != OK:
			result.error = "Could not update demo catalog sizes (error %d)." % catalog_error
			return result

	result.ok = true
	result.warehouse_path = warehouse_path
	result.gallery_path = gallery_path
	result.warehouse_size = warehouse_size
	result.gallery_size = gallery_size
	return result


static func _validate_sources() -> String:
	for path in _warehouse_files() + _gallery_files():
		if not FileAccess.file_exists(path):
			return "Missing demo pack source file: %s" % path

	return ""


static func _export_warehouse_pck(path: String) -> Error:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var packer: PCKPacker = PCKPacker.new()
	var error: Error = packer.pck_start(path)
	if error != OK:
		return error

	for source_path in _warehouse_files():
		error = packer.add_file(source_path, source_path)
		if error != OK:
			return error

	return packer.flush()


static func _export_gallery_zip(path: String) -> Error:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var writer: ZIPPacker = ZIPPacker.new()
	var error: Error = writer.open(path)
	if error != OK:
		return error

	writer.set_compression_level(ZIPPacker.COMPRESSION_NONE)
	for source_path in _gallery_files():
		error = _write_zip_source_file(writer, source_path)
		if error != OK:
			writer.close()
			return error

	return writer.close()


static func _warehouse_files() -> PackedStringArray:
	return PackedStringArray([
		"res://demo/packs/warehouse/main.tscn",
		"res://demo/packs/warehouse/box.tscn",
		"res://demo/packs/warehouse/warehouse_scene.gd",
		"res://demo/packs/warehouse/payload.bin",
	])


static func _gallery_files() -> PackedStringArray:
	return PackedStringArray([
		"res://demo/packs/gallery/main.tscn",
		"res://demo/packs/gallery/gallery_scene.gd",
		"res://demo/packs/gallery/payload.bin",
	])


static func _write_zip_source_file(writer: ZIPPacker, source_path: String) -> Error:
	var data: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
	if data.is_empty() and FileAccess.get_open_error() != OK:
		return FileAccess.get_open_error()

	var error: Error = writer.start_file(source_path.trim_prefix("res://"))
	if error != OK:
		return error

	error = writer.write_file(data)
	if error != OK:
		return error

	return writer.close_file()


static func _write_catalog_metadata(
	warehouse_size: int,
	gallery_size: int,
	warehouse_version_token: String,
	gallery_version_token: String
) -> Error:
	var text: String = FileAccess.get_file_as_string(_CATALOG_PATH)
	if text.is_empty():
		return FAILED

	if not _has_int_const(text, "WAREHOUSE_EXPECTED_SIZE") or not _has_int_const(text, "GALLERY_EXPECTED_SIZE"):
		return FAILED
	if not _has_string_const(text, "WAREHOUSE_VERSION_TOKEN") or not _has_string_const(text, "GALLERY_VERSION_TOKEN"):
		return FAILED

	text = _replace_int_const(text, "WAREHOUSE_EXPECTED_SIZE", warehouse_size)
	text = _replace_int_const(text, "GALLERY_EXPECTED_SIZE", gallery_size)
	text = _replace_string_const(text, "WAREHOUSE_VERSION_TOKEN", warehouse_version_token)
	text = _replace_string_const(text, "GALLERY_VERSION_TOKEN", gallery_version_token)

	var file: FileAccess = FileAccess.open(_CATALOG_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(text)
	return OK


static func _has_int_const(text: String, name: String) -> bool:
	return text.contains("const %s: int =" % name)


static func _has_string_const(text: String, name: String) -> bool:
	return text.contains("const %s: String =" % name)


static func _replace_int_const(text: String, name: String, value: int) -> String:
	var pattern: RegEx = RegEx.new()
	var error: Error = pattern.compile("const %s: int = \\d+" % name)
	if error != OK:
		return text

	return pattern.sub(text, "const %s: int = %d" % [name, value], false)


static func _replace_string_const(text: String, name: String, value: String) -> String:
	var pattern: RegEx = RegEx.new()
	var error: Error = pattern.compile("const %s: String = \"[^\"]*\"" % name)
	if error != OK:
		return text

	return pattern.sub(text, "const %s: String = \"%s\"" % [name, value], false)


static func _file_version_token(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return str(FileAccess.get_size(path))

	var hash: HashingContext = HashingContext.new()
	var error: Error = hash.start(HashingContext.HASH_SHA256)
	if error != OK:
		return str(FileAccess.get_size(path))

	var chunk: PackedByteArray = file.get_buffer(64 * 1024)
	while not chunk.is_empty():
		hash.update(chunk)
		chunk = file.get_buffer(64 * 1024)

	var digest: String = hash.finish().hex_encode().substr(0, 12)
	return "%d-%s" % [FileAccess.get_size(path), digest]
