extends Node

const CACHE_DIR: String = "user://pack_rat_http_pck_smoke_cache"
const SERVER_DIR: String = "user://pack_rat_http_pck_smoke_server"
const PACK_PATH: String = "user://pack_rat_http_pck_smoke_server/hub.pck"
const SOURCE_PATH: String = "user://pack_rat_http_pck_smoke_server/marker.txt"
const MOUNTED_MARKER: String = "res://pack_rat_http_pck_smoke/marker.txt"

var _server: TCPServer = TCPServer.new()
var _pack_bytes: PackedByteArray = []
var _url: String = ""
var _head_count: int = 0
var _get_count: int = 0
var _etag: String = "\"packrat-smoke-v1\""
var _last_modified: String = "Wed, 10 Jun 2026 20:15:00 GMT"
var _fail_get: bool = false


func _ready() -> void:
	set_process(false)
	_clear_directory(CACHE_DIR)
	_clear_directory(SERVER_DIR)
	_make_directory(SERVER_DIR)
	_build_pack("mounted-from-packrat")

	var listen_error: Error = _server.listen(0, "127.0.0.1")
	if listen_error != OK:
		_fail("Could not start local HTTP server (error %d)." % listen_error)
		return

	_url = "http://127.0.0.1:%d/hub.pck" % _server.get_local_port()
	set_process(true)
	await get_tree().process_frame

	var options: PackRatOptions = PackRatOptions.new()
	options.id = "http_pck_smoke"
	options.cache_dir = CACHE_DIR
	options.entry_path = MOUNTED_MARKER
	options.timeout_seconds = 10.0

	var first: PackRatResult = await PackRat.prepare(_url, options)
	if not first.ok or not first.mounted or first.from_cache:
		_fail("Expected first prepare to download and mount. Result: %s" % JSON.stringify(first.to_dictionary()))
		return

	if FileAccess.get_file_as_string(MOUNTED_MARKER).strip_edges() != "mounted-from-packrat":
		_fail("Mounted PCK marker was not readable from res://.")
		return

	var second: PackRatResult = await PackRat.prepare(_url, options)
	if not second.ok or not second.from_cache or not second.mounted:
		_fail("Expected second prepare to mount from cache. Result: %s" % JSON.stringify(second.to_dictionary()))
		return

	if _get_count != 1:
		_fail("Expected exactly one GET download, got %d." % _get_count)
		return

	if _head_count != 1:
		_fail("Expected one freshness HEAD request for cache hit, got %d." % _head_count)
		return

	var first_cache_path: String = first.local_path
	_etag = "\"packrat-smoke-v2\""
	_last_modified = "Wed, 10 Jun 2026 20:16:00 GMT"
	_build_pack("mounted-from-packrat-version-two")

	var third: PackRatResult = await PackRat.prepare(_url, options)
	if not third.ok or third.from_cache:
		_fail("Expected changed ETag to redownload. Result: %s" % JSON.stringify(third.to_dictionary()))
		return

	if third.local_path == first_cache_path:
		_fail("Expected stale redownload to use a new cache path, got %s." % third.local_path)
		return

	if _get_count != 2:
		_fail("Expected stale redownload to perform a second GET, got %d." % _get_count)
		return

	var metadata_head_count: int = _head_count
	var metadata_get_count: int = _get_count
	var metadata_options: PackRatOptions = PackRatOptions.new()
	metadata_options.id = "metadata_smoke"
	metadata_options.cache_dir = CACHE_DIR
	metadata_options.entry_path = MOUNTED_MARKER
	metadata_options.timeout_seconds = 10.0
	metadata_options.expected_size = _pack_bytes.size()
	metadata_options.expected_modified_time = 100

	var metadata_first: PackRatResult = await PackRat.prepare(_url, metadata_options)
	if not metadata_first.ok or metadata_first.from_cache:
		_fail("Expected metadata prepare to download. Result: %s" % JSON.stringify(metadata_first.to_dictionary()))
		return

	if _head_count != metadata_head_count:
		_fail("Expected metadata prepare to skip HEAD, got %d new HEAD requests." % (_head_count - metadata_head_count))
		return

	if _get_count != metadata_get_count + 1:
		_fail("Expected metadata prepare to download once, got %d new GET requests." % (_get_count - metadata_get_count))
		return

	var metadata_cache_path: String = metadata_first.local_path
	var metadata_second: PackRatResult = await PackRat.prepare(_url, metadata_options)
	if not metadata_second.ok or not metadata_second.from_cache:
		_fail("Expected metadata prepare to reuse cache. Result: %s" % JSON.stringify(metadata_second.to_dictionary()))
		return

	if _head_count != metadata_head_count or _get_count != metadata_get_count + 1:
		_fail("Expected metadata cache hit to skip HEAD and GET.")
		return

	_build_pack("metadata-version-two")
	metadata_options.expected_size = _pack_bytes.size()
	metadata_options.expected_modified_time = 101
	var metadata_third: PackRatResult = await PackRat.prepare(_url, metadata_options)
	if not metadata_third.ok or metadata_third.from_cache:
		_fail("Expected changed expected metadata to download. Result: %s" % JSON.stringify(metadata_third.to_dictionary()))
		return

	if metadata_third.local_path == metadata_cache_path:
		_fail("Expected changed expected metadata to use a new cache path.")
		return

	if _head_count != metadata_head_count or _get_count != metadata_get_count + 2:
		_fail("Expected changed metadata to skip HEAD and perform one more GET.")
		return

	var offline_head_count: int = _head_count
	var offline_get_count: int = _get_count
	var offline_options: PackRatOptions = PackRatOptions.new()
	offline_options.id = "offline_smoke"
	offline_options.cache_dir = CACHE_DIR
	offline_options.entry_path = MOUNTED_MARKER
	offline_options.timeout_seconds = 10.0
	offline_options.offline_first = true

	var offline_first: PackRatResult = await PackRat.prepare(_url, offline_options)
	if not offline_first.ok or offline_first.from_cache:
		_fail("Expected offline-first cache miss to download. Result: %s" % JSON.stringify(offline_first.to_dictionary()))
		return

	var offline_second: PackRatResult = await PackRat.prepare(_url, offline_options)
	if not offline_second.ok or not offline_second.from_cache:
		_fail("Expected offline-first cache hit to reuse cache. Result: %s" % JSON.stringify(offline_second.to_dictionary()))
		return

	if _head_count != offline_head_count or _get_count != offline_get_count + 1:
		_fail("Expected offline-first to skip HEAD and only download on miss.")
		return

	var concurrent_head_count: int = _head_count
	var concurrent_get_count: int = _get_count
	var concurrent_options: PackRatOptions = PackRatOptions.new()
	concurrent_options.id = "concurrent_smoke"
	concurrent_options.cache_dir = CACHE_DIR
	concurrent_options.entry_path = MOUNTED_MARKER
	concurrent_options.timeout_seconds = 10.0
	concurrent_options.expected_size = _pack_bytes.size()
	concurrent_options.expected_modified_time = 200
	var concurrent_results: Array[PackRatResult] = []
	_collect_prepare(concurrent_options, concurrent_results)
	_collect_prepare(concurrent_options, concurrent_results)

	var wait_until: int = Time.get_ticks_msec() + 3000
	while concurrent_results.size() < 2 and Time.get_ticks_msec() < wait_until:
		await get_tree().process_frame

	if concurrent_results.size() != 2:
		_fail("Timed out waiting for concurrent prepare results.")
		return

	for index in range(concurrent_results.size()):
		var concurrent_result: PackRatResult = concurrent_results[index]
		if not concurrent_result.ok:
			_fail("Expected concurrent prepare to succeed. Result: %s" % JSON.stringify(concurrent_result.to_dictionary()))
			return

	if _head_count != concurrent_head_count or _get_count != concurrent_get_count + 1:
		_fail("Expected concurrent prepares to share one download.")
		return

	var extensionless_options: PackRatOptions = PackRatOptions.new()
	extensionless_options.id = "extensionless_smoke"
	extensionless_options.cache_dir = CACHE_DIR
	extensionless_options.entry_path = MOUNTED_MARKER
	extensionless_options.timeout_seconds = 10.0
	var extensionless_url: String = "http://127.0.0.1:%d/download?id=hub" % _server.get_local_port()
	var extensionless: PackRatResult = await PackRat.prepare(extensionless_url, extensionless_options)
	if not extensionless.ok or not extensionless.mounted:
		_fail("Expected extensionless PCK URL to download and mount. Result: %s" % JSON.stringify(extensionless.to_dictionary()))
		return

	if extensionless.local_path.get_extension().to_lower() != "pck":
		_fail("Expected extensionless PCK URL to receive a .pck cache path, got %s." % extensionless.local_path)
		return

	var forced_options: PackRatOptions = PackRatOptions.new()
	forced_options.id = "forced_download_smoke"
	forced_options.cache_dir = CACHE_DIR
	forced_options.entry_path = MOUNTED_MARKER
	forced_options.timeout_seconds = 10.0
	var forced_first: PackRatResult = await PackRat.prepare(_url, forced_options)
	if not forced_first.ok:
		_fail("Expected forced-download setup prepare to succeed. Result: %s" % JSON.stringify(forced_first.to_dictionary()))
		return

	_fail_get = true
	forced_options.always_download = true
	var forced_second: PackRatResult = await PackRat.prepare(_url, forced_options)
	_fail_get = false
	if forced_second.ok:
		_fail("Expected always_download to fail when the fresh download fails.")
		return

	var invalid_url: String = "http://127.0.0.1:%d/invalid.pck" % _server.get_local_port()
	var invalid_options: PackRatOptions = PackRatOptions.new()
	invalid_options.id = "invalid_mount_smoke"
	invalid_options.cache_dir = CACHE_DIR
	invalid_options.timeout_seconds = 10.0
	var invalid_get_count: int = _get_count
	var invalid_first: PackRatResult = await PackRat.prepare(invalid_url, invalid_options)
	var invalid_second: PackRatResult = await PackRat.prepare(invalid_url, invalid_options)
	if invalid_first.ok or invalid_second.ok:
		_fail("Expected invalid PCK downloads to fail mounting.")
		return

	if _get_count != invalid_get_count + 2:
		_fail("Expected failed mounts to avoid cache reuse and download twice.")
		return

	print("PackRat HTTP PCK smoke passed. HEAD=%d GET=%d cache=%s" % [_head_count, _get_count, third.local_path])
	_server.stop()
	get_tree().quit()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		_serve_peer(peer)


func _serve_peer(peer: StreamPeerTCP) -> void:
	var request: String = ""
	var wait_until: int = Time.get_ticks_msec() + 1000

	while Time.get_ticks_msec() < wait_until and request.find("\r\n\r\n") < 0:
		if peer.get_available_bytes() > 0:
			request += peer.get_utf8_string(peer.get_available_bytes())
		else:
			await get_tree().process_frame

	var method: String = request.get_slice(" ", 0)
	var path: String = request.get_slice(" ", 1)
	if path == "/invalid.pck":
		if method == "HEAD":
			_head_count += 1
			_write_invalid_response(peer, false)
		elif method == "GET":
			_get_count += 1
			_write_invalid_response(peer, true)
		else:
			_write_not_found(peer)
	elif _fail_get and method == "GET":
		_get_count += 1
		_write_not_found(peer)
	elif method == "HEAD":
		_head_count += 1
		_write_response(peer, false)
	elif method == "GET":
		_get_count += 1
		_write_response(peer, true)
	else:
		_write_not_found(peer)

	peer.disconnect_from_host()


func _collect_prepare(options: PackRatOptions, output: Array[PackRatResult]) -> void:
	var result: PackRatResult = await PackRat.prepare(_url, options)
	output.append(result)


func _write_response(peer: StreamPeerTCP, include_body: bool) -> void:
	var headers: String = (
		"HTTP/1.1 200 OK\r\n"
		+ "Content-Type: application/octet-stream\r\n"
		+ "Content-Length: %d\r\n" % _pack_bytes.size()
		+ "ETag: %s\r\n" % _etag
		+ "Last-Modified: %s\r\n" % _last_modified
		+ "Access-Control-Allow-Origin: *\r\n"
		+ "Access-Control-Expose-Headers: ETag, Content-Length, Last-Modified\r\n"
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	peer.put_data(headers.to_utf8_buffer())

	if include_body:
		peer.put_data(_pack_bytes)


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


func _write_invalid_response(peer: StreamPeerTCP, include_body: bool) -> void:
	var body: PackedByteArray = "not a valid pack".to_utf8_buffer()
	var headers: String = (
		"HTTP/1.1 200 OK\r\n"
		+ "Content-Type: application/octet-stream\r\n"
		+ "Content-Length: %d\r\n" % body.size()
		+ "ETag: \"invalid-pack\"\r\n"
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	peer.put_data(headers.to_utf8_buffer())

	if include_body:
		peer.put_data(body)


func _build_pack(marker: String) -> void:
	var source: FileAccess = FileAccess.open(SOURCE_PATH, FileAccess.WRITE)
	if source == null:
		_fail("Could not write smoke source file (error %d)." % FileAccess.get_open_error())
		return

	source.store_string(marker)
	source = null

	var packer: PCKPacker = PCKPacker.new()
	var start_error: Error = packer.pck_start(PACK_PATH)
	if start_error != OK:
		_fail("Could not start PCK packer (error %d)." % start_error)
		return

	var add_error: Error = packer.add_file(MOUNTED_MARKER, SOURCE_PATH)
	if add_error != OK:
		_fail("Could not add smoke marker to PCK (error %d)." % add_error)
		return

	var flush_error: Error = packer.flush()
	if flush_error != OK:
		_fail("Could not flush smoke PCK (error %d)." % flush_error)
		return

	_pack_bytes = FileAccess.get_file_as_bytes(PACK_PATH)
	if _pack_bytes.is_empty():
		_fail("Smoke PCK was empty.")


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
		else:
			DirAccess.remove_absolute(child_path)
		child = dir.get_next()

	dir.list_dir_end()


func _fail(message: String) -> void:
	_server.stop()
	push_error(message)
	get_tree().quit(1)
