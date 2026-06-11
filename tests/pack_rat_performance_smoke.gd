extends Node

const CACHE_DIR: String = "user://pack_rat_performance_smoke_cache"
const SERVER_DIR: String = "user://pack_rat_performance_smoke_server"
const PACK_PATH: String = "user://pack_rat_performance_smoke_server/perf.pck"
const MARKER_SOURCE_PATH: String = "user://pack_rat_performance_smoke_server/marker.txt"
const PAYLOAD_SOURCE_PATH: String = "user://pack_rat_performance_smoke_server/payload.bin"
const MOUNTED_MARKER: String = "res://pack_rat_performance_smoke/marker.txt"
const MOUNTED_PAYLOAD: String = "res://pack_rat_performance_smoke/payload.bin"
const LEGACY_CHUNK_SIZE: int = 64 * 1024
const OPTIMIZED_CHUNK_SIZE: int = 4 * 1024 * 1024
const PAYLOAD_BYTES: int = 10 * 1024 * 1024
const SERVER_CHUNK_SIZE: int = 4 * 1024 * 1024

var _server: TCPServer = TCPServer.new()
var _pack_bytes: PackedByteArray = []
var _url: String = ""
var _active_peers: int = 0


func _ready() -> void:
	Engine.max_fps = 60
	set_process(false)
	_clear_directory(CACHE_DIR)
	_clear_directory(SERVER_DIR)
	_make_directory(SERVER_DIR)
	_build_pack()

	var listen_error: Error = _server.listen(0, "127.0.0.1")
	if listen_error != OK:
		_fail("Could not start performance HTTP server (error %d)." % listen_error)
		return

	_url = "http://127.0.0.1:%d/perf.pck" % _server.get_local_port()
	set_process(true)
	await get_tree().process_frame

	var legacy: PackRatResult = await _load_case("legacy_64k", LEGACY_CHUNK_SIZE)
	if not legacy.ok:
		return

	var optimized: PackRatResult = await _load_case("optimized_4m", OPTIMIZED_CHUNK_SIZE)
	if not optimized.ok:
		return

	var legacy_frames: int = int(legacy.timings_msec.get("download_http_progress_frames", 0))
	var optimized_frames: int = int(optimized.timings_msec.get("download_http_progress_frames", 0))
	if legacy_frames <= optimized_frames:
		_fail("Expected 64 KiB HTTP chunks to need more progress frames than 4 MiB chunks. legacy=%d optimized=%d" % [legacy_frames, optimized_frames])
		return

	await _finish_success("PackRat performance smoke passed. legacy=%s optimized=%s" % [
		JSON.stringify(legacy.timings_msec),
		JSON.stringify(optimized.timings_msec),
	])


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		_serve_peer(peer)


func _load_case(id: String, download_chunk_size: int) -> PackRatResult:
	var options: PackRatOptions = PackRatOptions.new()
	options.id = id
	options.cache_dir = CACHE_DIR
	options.entry_path = MOUNTED_MARKER
	options.expected_size = _pack_bytes.size()
	options.timeout_seconds = 30.0
	options.download_chunk_size = download_chunk_size

	var progress_events: Array[int] = [0]
	var request: PackRatRequest = PackRat.load_resource_pack_async(_url, options)
	request.progress_changed.connect(func(_downloaded_bytes: int, _total_bytes: int) -> void:
		progress_events[0] += 1
	)
	await request.completed
	var result: PackRatResult = request.result
	if result == null:
		_fail("Expected performance case %s to produce a result." % id)
		return PackRatResult.failed(_url, "Missing result.")

	result.timings_msec["signal_progress_events"] = progress_events[0]
	result.timings_msec["configured_download_chunk_size"] = download_chunk_size
	if not result.ok:
		_fail("Expected performance case %s to load. Result: %s" % [id, JSON.stringify(result.to_dictionary())])
		return result

	if progress_events[0] <= 0:
		_fail("Expected performance case %s to emit progress_changed at least once." % id)
		return result

	for key in [
		"download_msec",
		"download_http_progress_frames",
		"download_http_transfer_msec",
		"cache_finalize_msec",
		"mount_msec",
		"total_msec",
	]:
		if not result.timings_msec.has(key):
			_fail("Expected performance case %s timings to include %s. Result: %s" % [id, key, JSON.stringify(result.to_dictionary())])
			return result

	print("PackRat performance smoke %s timings %s" % [id, JSON.stringify(result.timings_msec)])
	return result


func _serve_peer(peer: StreamPeerTCP) -> void:
	_active_peers += 1
	var request: String = ""
	var wait_until: int = Time.get_ticks_msec() + 1000

	while Time.get_ticks_msec() < wait_until and request.find("\r\n\r\n") < 0:
		if peer.get_available_bytes() > 0:
			request += peer.get_utf8_string(peer.get_available_bytes())
		else:
			await get_tree().process_frame

	var method: String = request.get_slice(" ", 0)
	var path: String = request.get_slice(" ", 1).get_slice("?", 0)
	if path != "/perf.pck":
		_write_not_found(peer)
	elif method == "HEAD":
		_write_response(peer, false)
	elif method == "GET":
		await _write_response(peer, true)
	else:
		_write_not_found(peer)

	peer.disconnect_from_host()
	peer = null
	_active_peers -= 1


func _write_response(peer: StreamPeerTCP, include_body: bool) -> void:
	var headers: String = (
		"HTTP/1.1 200 OK\r\n"
		+ "Content-Type: application/octet-stream\r\n"
		+ "Content-Length: %d\r\n" % _pack_bytes.size()
		+ "ETag: \"packrat-performance-smoke\"\r\n"
		+ "Access-Control-Allow-Origin: *\r\n"
		+ "Access-Control-Expose-Headers: ETag, Content-Length\r\n"
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	peer.put_data(headers.to_utf8_buffer())

	if not include_body:
		return

	var offset: int = 0
	while offset < _pack_bytes.size():
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return

		var chunk: PackedByteArray = _pack_bytes.slice(offset, mini(offset + SERVER_CHUNK_SIZE, _pack_bytes.size()))
		var write_result: Array = peer.put_partial_data(chunk)
		var error: Error = write_result[0]
		var written: int = int(write_result[1])
		if error != OK:
			return
		if written <= 0:
			await get_tree().process_frame
			continue

		offset += written
		await get_tree().process_frame


func _write_not_found(peer: StreamPeerTCP) -> void:
	var body: PackedByteArray = "not found".to_utf8_buffer()
	var headers: String = (
		"HTTP/1.1 404 Not Found\r\n"
		+ "Content-Length: %d\r\n" % body.size()
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	peer.put_data(headers.to_utf8_buffer())
	peer.put_data(body)


func _build_pack() -> void:
	var marker: FileAccess = FileAccess.open(MARKER_SOURCE_PATH, FileAccess.WRITE)
	if marker == null:
		_fail("Could not write performance marker source (error %d)." % FileAccess.get_open_error())
		return

	marker.store_string("performance-smoke")
	marker = null

	var payload: FileAccess = FileAccess.open(PAYLOAD_SOURCE_PATH, FileAccess.WRITE)
	if payload == null:
		_fail("Could not write performance payload source (error %d)." % FileAccess.get_open_error())
		return

	var block: PackedByteArray = PackedByteArray()
	block.resize(1024 * 1024)
	for index in range(block.size()):
		block[index] = (index * 31 + 17) & 0xff

	for _block_index in range(int(PAYLOAD_BYTES / block.size())):
		payload.store_buffer(block)
	payload = null

	var packer: PCKPacker = PCKPacker.new()
	var start_error: Error = packer.pck_start(PACK_PATH)
	if start_error != OK:
		_fail("Could not start performance PCK packer (error %d)." % start_error)
		return

	var add_error: Error = packer.add_file(MOUNTED_MARKER, MARKER_SOURCE_PATH)
	if add_error != OK:
		_fail("Could not add performance marker to PCK (error %d)." % add_error)
		return

	add_error = packer.add_file(MOUNTED_PAYLOAD, PAYLOAD_SOURCE_PATH)
	if add_error != OK:
		_fail("Could not add performance payload to PCK (error %d)." % add_error)
		return

	var flush_error: Error = packer.flush()
	if flush_error != OK:
		_fail("Could not flush performance PCK (error %d)." % flush_error)
		return

	_pack_bytes = FileAccess.get_file_as_bytes(PACK_PATH)
	if _pack_bytes.is_empty():
		_fail("Performance PCK was empty.")


func _make_directory(path: String) -> void:
	var error: Error = DirAccess.make_dir_recursive_absolute(path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		_fail("Could not create directory %s (error %d)." % [path, error])


func _clear_directory(path: String) -> void:
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


func _fail(message: String) -> void:
	_server.stop()
	push_error(message)
	get_tree().quit(1)


func _finish_success(message: String) -> void:
	set_process(false)
	var wait_until: int = Time.get_ticks_msec() + 3000
	while _active_peers > 0 and Time.get_ticks_msec() < wait_until:
		await get_tree().process_frame

	print(message)
	_server.stop()
	get_tree().quit()
