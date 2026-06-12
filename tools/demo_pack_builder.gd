class_name PackRatDemoPackBuilder extends SceneTree
## Builds the generated PCK and ZIP packs used by the PackRat Portal demo.

## Default output directory for generated demo packs.
const DEFAULT_OUTPUT_DIR: String = "build/packs"

## Warehouse PCK payload target.
const WAREHOUSE_PAYLOAD_BYTES: int = 10 * 1024 * 1024

## Gallery ZIP payload target.
const GALLERY_PAYLOAD_BYTES: int = 16 * 1024 * 1024

const _CATALOG_PATH: String = "res://demo/demo_catalog.gd"
const _WAREHOUSE_SCRIPT: String = "res://packrat_demo/warehouse/warehouse_scene.gd"
const _WAREHOUSE_PAYLOAD: String = "res://packrat_demo/warehouse/payload.bin"
const _GALLERY_SCRIPT: String = "res://packrat_demo/gallery/gallery_scene.gd"
const _GALLERY_PAYLOAD: String = "res://packrat_demo/gallery/payload.bin"
const _PACK_ICON: String = "res://addons/pack_rat/icon.svg"
const _OUTPUT_ARG: String = "--output-dir="
const _NO_CATALOG_ARG: String = "--no-catalog"
const _TEMP_DIR: String = "user://pack_rat_demo_pack_builder"


func _init() -> void:
	var output_dir: String = DEFAULT_OUTPUT_DIR
	var write_catalog: bool = true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(_OUTPUT_ARG):
			output_dir = argument.substr(_OUTPUT_ARG.length())
		elif argument == _NO_CATALOG_ARG:
			write_catalog = false

	var result: Dictionary = build_all(output_dir, write_catalog)
	if not bool(result.get("ok", false)):
		printerr(result.get("error", "Unknown demo pack build error."))
		quit(1)
		return

	print(JSON.stringify(result, "\t"))
	quit()


## Builds both demo packs and optionally writes generated sizes into the catalog.
static func build_all(output_dir: String = DEFAULT_OUTPUT_DIR, write_catalog: bool = true) -> Dictionary:
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

	var warehouse_path: String = output_dir.path_join(PackRatDemoCatalog.WAREHOUSE_FILE_NAME)
	var gallery_path: String = output_dir.path_join(PackRatDemoCatalog.GALLERY_FILE_NAME)
	_clear_directory(_TEMP_DIR)

	var warehouse_error: Error = _build_warehouse_pck(warehouse_path, _TEMP_DIR.path_join("warehouse"))
	if warehouse_error != OK:
		result.error = "Could not build warehouse PCK (error %d)." % warehouse_error
		return result

	var gallery_error: Error = _build_gallery_zip(gallery_path)
	if gallery_error != OK:
		result.error = "Could not build gallery ZIP (error %d)." % gallery_error
		return result

	var warehouse_size: int = FileAccess.get_size(warehouse_path)
	var gallery_size: int = FileAccess.get_size(gallery_path)
	if warehouse_size <= 0 or gallery_size <= 0:
		result.error = "Generated demo packs were empty."
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
	_clear_directory(_TEMP_DIR)
	return result


static func _build_warehouse_pck(path: String, temp_dir: String) -> Error:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var make_error: Error = DirAccess.make_dir_recursive_absolute(temp_dir)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return make_error

	var scene_path: String = temp_dir.path_join("main.tscn")
	var script_path: String = temp_dir.path_join("warehouse_scene.gd")
	var payload_path: String = temp_dir.path_join("payload.bin")
	var write_error: Error = _write_text_file(scene_path, _warehouse_scene())
	if write_error != OK:
		return write_error
	write_error = _write_text_file(script_path, _warehouse_script())
	if write_error != OK:
		return write_error
	write_error = _write_binary_file(payload_path, _payload_bytes(WAREHOUSE_PAYLOAD_BYTES, 73))
	if write_error != OK:
		return write_error

	var packer: PCKPacker = PCKPacker.new()
	var error: Error = packer.pck_start(path)
	if error != OK:
		return error

	error = packer.add_file(PackRatDemoCatalog.WAREHOUSE_ENTRY_PATH, scene_path)
	if error != OK:
		return error

	error = packer.add_file(_WAREHOUSE_SCRIPT, script_path)
	if error != OK:
		return error

	error = packer.add_file(_WAREHOUSE_PAYLOAD, payload_path)
	if error != OK:
		return error

	return packer.flush()


static func _build_gallery_zip(path: String) -> Error:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var writer: ZIPPacker = ZIPPacker.new()
	var error: Error = writer.open(path)
	if error != OK:
		return error

	writer.set_compression_level(ZIPPacker.COMPRESSION_NONE)
	error = _write_zip_file(writer, PackRatDemoCatalog.GALLERY_ENTRY_PATH, _gallery_scene().to_utf8_buffer())
	if error != OK:
		writer.close()
		return error

	error = _write_zip_file(writer, _GALLERY_SCRIPT, _gallery_script().to_utf8_buffer())
	if error != OK:
		writer.close()
		return error

	error = _write_zip_file(writer, _GALLERY_PAYLOAD, _payload_bytes(GALLERY_PAYLOAD_BYTES, 137))
	if error != OK:
		writer.close()
		return error

	return writer.close()


static func _write_zip_file(writer: ZIPPacker, target_path: String, data: PackedByteArray) -> Error:
	var error: Error = writer.start_file(target_path.trim_prefix("res://"))
	if error != OK:
		return error

	error = writer.write_file(data)
	if error != OK:
		return error

	return writer.close_file()


static func _write_text_file(path: String, text: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(text)
	return OK


static func _write_binary_file(path: String, data: PackedByteArray) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_buffer(data)
	return OK


static func _clear_directory(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var child: String = dir.get_next()
	while not child.is_empty():
		var child_path: String = path.path_join(child)
		if dir.current_is_dir():
			_clear_directory(child_path)
			DirAccess.remove_absolute(child_path)
		else:
			DirAccess.remove_absolute(child_path)
		child = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


static func _payload_bytes(size: int, seed: int) -> PackedByteArray:
	var chunk: PackedByteArray = PackedByteArray()
	chunk.resize(64 * 1024)
	var value: int = seed
	for index in range(chunk.size()):
		value = (value * 1103515245 + 12345) & 0x7fffffff
		chunk[index] = (value >> 8) & 0xff

	var data: PackedByteArray = PackedByteArray()
	var remaining: int = size
	while remaining >= chunk.size():
		data.append_array(chunk)
		remaining -= chunk.size()

	if remaining > 0:
		data.append_array(chunk.slice(0, remaining))

	return data


static func _warehouse_scene() -> String:
	var lines: PackedStringArray = PackedStringArray([
		"[gd_scene load_steps=3 format=3]",
		"",
		"[ext_resource type=\"Script\" path=\"%s\" id=\"1_scene\"]" % _WAREHOUSE_SCRIPT,
		"[ext_resource type=\"Texture2D\" path=\"%s\" id=\"2_icon\"]" % _PACK_ICON,
		"",
		"[node name=\"Warehouse\" type=\"Control\"]",
		"layout_mode = 3",
		"anchors_preset = 15",
		"anchor_right = 1.0",
		"anchor_bottom = 1.0",
		"grow_horizontal = 2",
		"grow_vertical = 2",
		"script = ExtResource(\"1_scene\")",
		"",
		"[node name=\"Page\" type=\"MarginContainer\" parent=\".\"]",
		"layout_mode = 1",
		"anchors_preset = 15",
		"anchor_right = 1.0",
		"anchor_bottom = 1.0",
		"grow_horizontal = 2",
		"grow_vertical = 2",
		"theme_override_constants/margin_left = 10",
		"theme_override_constants/margin_top = 10",
		"theme_override_constants/margin_right = 10",
		"theme_override_constants/margin_bottom = 10",
		"",
		"[node name=\"Header\" type=\"HBoxContainer\" parent=\"Page\"]",
		"layout_mode = 2",
		"theme_override_constants/separation = 10",
		"",
		"[node name=\"Title\" type=\"Label\" parent=\"Page/Header\"]",
		"layout_mode = 2",
		"theme_override_colors/font_color = Color(0.541176, 0.341176, 0.160784, 1)",
		"theme_override_font_sizes/font_size = 18",
		"text = \"Warehouse PCK\"",
		"vertical_alignment = 1",
		"",
		"[node name=\"Subtitle\" type=\"Label\" parent=\"Page/Header\"]",
		"layout_mode = 2",
		"size_flags_horizontal = 3",
		"theme_override_colors/font_color = Color(0.352941, 0.313726, 0.27451, 1)",
		"theme_override_font_sizes/font_size = 12",
		"text = \"Moving PackRat box room\"",
		"vertical_alignment = 1",
		"",
		"[node name=\"MascotWatermark\" type=\"TextureRect\" parent=\".\"]",
		"layout_mode = 1",
		"anchors_preset = 3",
		"anchor_left = 1.0",
		"anchor_right = 1.0",
		"offset_left = -210.0",
		"offset_top = 18.0",
		"offset_right = -34.0",
		"offset_bottom = 194.0",
		"grow_horizontal = 0",
		"texture = ExtResource(\"2_icon\")",
		"expand_mode = 1",
		"stretch_mode = 5",
		"modulate = Color(1, 0.82, 0.58, 0.88)",
		"",
		"[node name=\"Floor\" type=\"ColorRect\" parent=\".\"]",
		"layout_mode = 1",
		"anchor_top = 1.0",
		"anchor_right = 1.0",
		"anchor_bottom = 1.0",
		"offset_top = -34.0",
		"offset_bottom = -10.0",
		"grow_horizontal = 2",
		"grow_vertical = 0",
		"color = Color(0.541176, 0.341176, 0.160784, 1)",
		"",
	])

	for index in range(26):
		var column: int = index % 9
		var row: int = int(index / 9)
		var size: float = 44.0 + float(index % 4) * 8.0
		var left: float = 60.0 + float(column) * 76.0
		var top: float = 110.0 + float(row) * 42.0

		lines.append("[node name=\"Box%02d\" type=\"TextureRect\" parent=\".\"]" % index)
		lines.append("layout_mode = 0")
		lines.append("offset_left = %.1f" % left)
		lines.append("offset_top = %.1f" % top)
		lines.append("offset_right = %.1f" % (left + size))
		lines.append("offset_bottom = %.1f" % (top + size))
		lines.append("pivot_offset = Vector2(%.1f, %.1f)" % [size * 0.5, size * 0.5])
		lines.append("texture = ExtResource(\"2_icon\")")
		lines.append("expand_mode = 1")
		lines.append("stretch_mode = 5")
		lines.append("")

	return "\n".join(lines)


static func _warehouse_script() -> String:
	return "\n".join(PackedStringArray([
		"extends Control",
		"",
		"var _boxes: Array[TextureRect] = []",
		"var _velocities: Array[Vector2] = []",
		"var _spins: Array[float] = []",
		"",
		"func _ready() -> void:",
		"\tclip_contents = true",
		"\tfor index in range(26):",
		"\t\tvar node: Node = get_node(\"Box%02d\" % index)",
		"\t\tif node is TextureRect:",
		"\t\t\tvar box: TextureRect = node",
		"\t\t\t_boxes.append(box)",
		"\t\t\t_velocities.append(Vector2(-120.0 + float((index * 37) % 240), -40.0 - float((index * 19) % 170)))",
		"\t\t\t_spins.append(-2.1 + float((index * 11) % 42) / 10.0)",
		"",
		"func _process(delta: float) -> void:",
		"\tvar bounds: Vector2 = size",
		"\tif bounds.x <= 0.0 or bounds.y <= 0.0:",
		"\t\tbounds = Vector2(900.0, 520.0)",
		"\tfor index in range(_boxes.size()):",
		"\t\tvar box: TextureRect = _boxes[index]",
		"\t\tvar velocity: Vector2 = _velocities[index]",
		"\t\tvelocity.y += 520.0 * delta",
		"\t\tbox.position += velocity * delta",
		"\t\tbox.rotation += _spins[index] * delta",
		"\t\tif box.position.x < 22.0 or box.position.x + box.size.x > bounds.x - 22.0:",
		"\t\t\tvelocity.x *= -0.86",
		"\t\t\tbox.position.x = clampf(box.position.x, 22.0, bounds.x - 22.0 - box.size.x)",
		"\t\tif box.position.y + box.size.y > bounds.y - 34.0:",
		"\t\t\tvelocity.y *= -0.72",
		"\t\t\tvelocity.x *= 0.985",
		"\t\t\tbox.position.y = bounds.y - 34.0 - box.size.y",
		"\t\t_velocities[index] = velocity",
		"",
	]))


static func _gallery_scene() -> String:
	var lines: PackedStringArray = PackedStringArray([
		"[gd_scene load_steps=4 format=3]",
		"",
		"[ext_resource type=\"Script\" path=\"%s\" id=\"1_scene\"]" % _GALLERY_SCRIPT,
		"[ext_resource type=\"Texture2D\" path=\"%s\" id=\"2_icon\"]" % _PACK_ICON,
		"",
		"[sub_resource type=\"StyleBoxFlat\" id=\"TilePanel\"]",
		"bg_color = Color(1, 1, 1, 1)",
		"border_width_left = 1",
		"border_width_top = 1",
		"border_width_right = 1",
		"border_width_bottom = 1",
		"border_color = Color(0.717647, 0.831373, 0.792157, 1)",
		"corner_radius_top_left = 8",
		"corner_radius_top_right = 8",
		"corner_radius_bottom_right = 8",
		"corner_radius_bottom_left = 8",
		"",
		"[node name=\"Gallery\" type=\"Control\"]",
		"layout_mode = 3",
		"anchors_preset = 15",
		"anchor_right = 1.0",
		"anchor_bottom = 1.0",
		"grow_horizontal = 2",
		"grow_vertical = 2",
		"script = ExtResource(\"1_scene\")",
		"",
		"[node name=\"Page\" type=\"MarginContainer\" parent=\".\"]",
		"layout_mode = 1",
		"anchors_preset = 15",
		"anchor_right = 1.0",
		"anchor_bottom = 1.0",
		"grow_horizontal = 2",
		"grow_vertical = 2",
		"theme_override_constants/margin_left = 10",
		"theme_override_constants/margin_top = 10",
		"theme_override_constants/margin_right = 10",
		"theme_override_constants/margin_bottom = 10",
		"",
		"[node name=\"Stack\" type=\"VBoxContainer\" parent=\"Page\"]",
		"layout_mode = 2",
		"theme_override_constants/separation = 10",
		"",
		"[node name=\"Header\" type=\"HBoxContainer\" parent=\"Page/Stack\"]",
		"layout_mode = 2",
		"theme_override_constants/separation = 10",
		"",
		"[node name=\"Title\" type=\"Label\" parent=\"Page/Stack/Header\"]",
		"layout_mode = 2",
		"theme_override_colors/font_color = Color(0.121569, 0.294118, 0.262745, 1)",
		"theme_override_font_sizes/font_size = 18",
		"text = \"Gallery ZIP\"",
		"vertical_alignment = 1",
		"",
		"[node name=\"Subtitle\" type=\"Label\" parent=\"Page/Stack/Header\"]",
		"layout_mode = 2",
		"size_flags_horizontal = 3",
		"theme_override_colors/font_color = Color(0.262745, 0.392157, 0.360784, 1)",
		"theme_override_font_sizes/font_size = 12",
		"text = \"Responsive content tile gallery\"",
		"vertical_alignment = 1",
		"",
		"[node name=\"CardScroll\" type=\"ScrollContainer\" parent=\"Page/Stack\"]",
		"layout_mode = 2",
		"size_flags_vertical = 3",
		"horizontal_scroll_mode = 0",
		"",
		"[node name=\"TileFlow\" type=\"HFlowContainer\" parent=\"Page/Stack/CardScroll\"]",
		"layout_mode = 2",
		"size_flags_horizontal = 3",
		"theme_override_constants/h_separation = 10",
		"theme_override_constants/v_separation = 10",
		"",
	])

	for index in range(12):
		var swatch: String = "Color(0.152941, 0.501961, 0.423529, 1)"
		if index % 2 != 0:
			swatch = "Color(0.541176, 0.341176, 0.160784, 1)"

		lines.append("[node name=\"Tile%02d\" type=\"PanelContainer\" parent=\"Page/Stack/CardScroll/TileFlow\"]" % index)
		lines.append("custom_minimum_size = Vector2(160, 108)")
		lines.append("layout_mode = 2")
		lines.append("theme_override_styles/panel = SubResource(\"TilePanel\")")
		lines.append("")
		var tile_path: String = "Page/Stack/CardScroll/TileFlow/Tile%02d" % index
		lines.append("[node name=\"Swatch\" type=\"ColorRect\" parent=\"%s\"]" % tile_path)
		lines.append("layout_mode = 0")
		lines.append("offset_left = 14.0")
		lines.append("offset_top = 12.0")
		lines.append("offset_right = 166.0")
		lines.append("offset_bottom = 40.0")
		lines.append("color = %s" % swatch)
		lines.append("")
		lines.append("[node name=\"Icon\" type=\"TextureRect\" parent=\"%s\"]" % tile_path)
		lines.append("layout_mode = 0")
		lines.append("offset_left = 22.0")
		lines.append("offset_top = 44.0")
		lines.append("offset_right = 74.0")
		lines.append("offset_bottom = 96.0")
		lines.append("texture = ExtResource(\"2_icon\")")
		lines.append("expand_mode = 1")
		lines.append("stretch_mode = 5")
		lines.append("")
		lines.append("[node name=\"Label\" type=\"Label\" parent=\"%s\"]" % tile_path)
		lines.append("layout_mode = 0")
		lines.append("offset_left = 82.0")
		lines.append("offset_top = 50.0")
		lines.append("offset_right = 154.0")
		lines.append("offset_bottom = 84.0")
		lines.append("theme_override_colors/font_color = Color(0.121569, 0.168627, 0.160784, 1)")
		lines.append("theme_override_font_sizes/font_size = 12")
		lines.append("text = \"Content tile %02d\"" % (index + 1))
		lines.append("autowrap_mode = 3")
		lines.append("")

	return "\n".join(lines)


static func _gallery_script() -> String:
	return "\n".join(PackedStringArray([
		"extends Control",
		"",
		"var _cards: Array[PanelContainer] = []",
		"",
		"func _ready() -> void:",
		"\tfor index in range(12):",
		"\t\tvar node: Node = find_child(\"Tile%02d\" % index, true, false)",
		"\t\tif node is PanelContainer:",
		"\t\t\tvar card: PanelContainer = node",
		"\t\t\t_cards.append(card)",
		"",
		"func _process(_delta: float) -> void:",
		"\tfor index in range(_cards.size()):",
		"\t\tvar card: PanelContainer = _cards[index]",
		"\t\tcard.pivot_offset = card.size * 0.5",
		"\t\tvar pulse: float = sin(Time.get_ticks_msec() * 0.0015 + float(index)) * 0.015",
		"\t\tcard.scale = Vector2.ONE * (1.0 + pulse)",
		"",
	]))


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
	var marker: String = "const %s: int = " % name
	return text.find(marker) >= 0


static func _has_string_const(text: String, name: String) -> bool:
	var marker: String = "const %s: String = " % name
	return text.find(marker) >= 0


static func _replace_int_const(text: String, name: String, value: int) -> String:
	var marker: String = "const %s: int = " % name
	var start: int = text.find(marker)
	if start < 0:
		return text

	var value_start: int = start + marker.length()
	var line_end: int = text.find("\n", value_start)
	if line_end < 0:
		line_end = text.length()

	return text.substr(0, value_start) + str(value) + text.substr(line_end)


static func _replace_string_const(text: String, name: String, value: String) -> String:
	var marker: String = "const %s: String = " % name
	var start: int = text.find(marker)
	if start < 0:
		return text

	var value_start: int = start + marker.length()
	var line_end: int = text.find("\n", value_start)
	if line_end < 0:
		line_end = text.length()

	return text.substr(0, value_start) + "\"%s\"" % value.c_escape() + text.substr(line_end)


static func _file_version_token(path: String) -> String:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return str(FileAccess.get_size(path))

	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return "%d-%s" % [bytes.size(), context.finish().hex_encode().substr(0, 12)]
