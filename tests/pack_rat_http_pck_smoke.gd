extends Node

const CACHE_DIR := "user://pack_rat_http_pck_smoke_cache"
const SERVER_DIR := "user://pack_rat_http_pck_smoke_server"
const PACK_PATH := "user://pack_rat_http_pck_smoke_server/hub.pck"
const SOURCE_PATH := "user://pack_rat_http_pck_smoke_server/marker.txt"
const MOUNTED_MARKER := "res://pack_rat_http_pck_smoke/marker.txt"

var _server := TCPServer.new()
var _pack_bytes: PackedByteArray = []
var _url := ""
var _head_count := 0
var _get_count := 0
var _etag := "\"packrat-smoke-v1\""
var _last_modified := "Wed, 10 Jun 2026 20:15:00 GMT"


func _ready() -> void:
	set_process(false)
	_clear_directory(CACHE_DIR)
	_clear_directory(SERVER_DIR)
	_make_directory(SERVER_DIR)
	_build_pack("mounted-from-packrat")

	var listen_error := _server.listen(0, "127.0.0.1")
	if listen_error != OK:
		_fail("Could not start local HTTP server (error %d)." % listen_error)
		return

	_url = "http://127.0.0.1:%d/hub.pck" % _server.get_local_port()
	set_process(true)
	await get_tree().process_frame

	var options := PackRatOptions.new()
	options.id = "http_pck_smoke"
	options.cache_dir = CACHE_DIR
	options.entry_path = MOUNTED_MARKER
	options.head_timeout_seconds = 2.0
	options.timeout_seconds = 0.0

	var first := await PackRat.prepare(_url, options)
	if not first.ok or not first.mounted or first.from_cache:
		_fail("Expected first prepare to download and mount. Result: %s" % JSON.stringify(first.to_dictionary()))
		return

	if FileAccess.get_file_as_string(MOUNTED_MARKER).strip_edges() != "mounted-from-packrat":
		_fail("Mounted PCK marker was not readable from res://.")
		return

	var second := await PackRat.prepare(_url, options)
	if not second.ok or not second.from_cache or not second.mounted:
		_fail("Expected second prepare to mount from cache. Result: %s" % JSON.stringify(second.to_dictionary()))
		return

	if _get_count != 1:
		_fail("Expected exactly one GET download, got %d." % _get_count)
		return

	if _head_count < 2:
		_fail("Expected freshness HEAD requests for download and cache hit, got %d." % _head_count)
		return

	var first_cache_path := first.local_path
	_etag = "\"packrat-smoke-v2\""
	_last_modified = "Wed, 10 Jun 2026 20:16:00 GMT"
	_build_pack("mounted-from-packrat-version-two")

	var third := await PackRat.prepare(_url, options)
	if not third.ok or third.from_cache:
		_fail("Expected changed ETag to redownload. Result: %s" % JSON.stringify(third.to_dictionary()))
		return

	if third.local_path == first_cache_path:
		_fail("Expected stale redownload to use a new cache path, got %s." % third.local_path)
		return

	if _get_count != 2:
		_fail("Expected stale redownload to perform a second GET, got %d." % _get_count)
		return

	print("PackRat HTTP PCK smoke passed. HEAD=%d GET=%d cache=%s" % [_head_count, _get_count, third.local_path])
	_server.stop()
	get_tree().quit()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		_serve_peer(peer)


func _serve_peer(peer: StreamPeerTCP) -> void:
	var request := ""
	var wait_until := Time.get_ticks_msec() + 1000

	while Time.get_ticks_msec() < wait_until and request.find("\r\n\r\n") < 0:
		if peer.get_available_bytes() > 0:
			request += peer.get_utf8_string(peer.get_available_bytes())
		else:
			await get_tree().process_frame

	var method := request.get_slice(" ", 0)
	if method == "HEAD":
		_head_count += 1
		_write_response(peer, false)
	elif method == "GET":
		_get_count += 1
		_write_response(peer, true)
	else:
		_write_not_found(peer)

	peer.disconnect_from_host()


func _write_response(peer: StreamPeerTCP, include_body: bool) -> void:
	var headers := (
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
	var body := "not found".to_utf8_buffer()
	var headers := (
		"HTTP/1.1 404 Not Found\r\n"
		+ "Content-Length: %d\r\n" % body.size()
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	peer.put_data(headers.to_utf8_buffer())
	peer.put_data(body)


func _build_pack(marker: String) -> void:
	var source := FileAccess.open(SOURCE_PATH, FileAccess.WRITE)
	if source == null:
		_fail("Could not write smoke source file (error %d)." % FileAccess.get_open_error())
		return

	source.store_string(marker)
	source = null

	var packer := PCKPacker.new()
	var start_error := packer.pck_start(PACK_PATH)
	if start_error != OK:
		_fail("Could not start PCK packer (error %d)." % start_error)
		return

	var add_error := packer.add_file(MOUNTED_MARKER, SOURCE_PATH)
	if add_error != OK:
		_fail("Could not add smoke marker to PCK (error %d)." % add_error)
		return

	var flush_error := packer.flush()
	if flush_error != OK:
		_fail("Could not flush smoke PCK (error %d)." % flush_error)
		return

	_pack_bytes = FileAccess.get_file_as_bytes(PACK_PATH)
	if _pack_bytes.is_empty():
		_fail("Smoke PCK was empty.")


func _make_directory(path: String) -> void:
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		_fail("Could not create directory %s (error %d)." % [path, error])


func _clear_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var child := dir.get_next()
	while not child.is_empty():
		var child_path := path.path_join(child)
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
