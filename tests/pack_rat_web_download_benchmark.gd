extends Control

const CACHE_DIR: String = "user://pack_rat_web_download_benchmark_cache"
const PACK_URL: String = "packs/packrat-demo-warehouse.pck"
const CHUNK_SIZES: Array[int] = [
	4 * 1024 * 1024,
	8 * 1024 * 1024,
	16 * 1024 * 1024,
]


func _ready() -> void:
	if not OS.has_feature("web"):
		print("WEB_BENCH skipped: Web export only.")
		get_tree().quit()
		return

	await get_tree().process_frame
	var url: String = _absolute_pack_url()
	print("WEB_BENCH start url=%s" % url)
	var clear_options: PackRatOptions = PackRatOptions.new()
	clear_options.cache_dir = CACHE_DIR
	PackRat.clear_cache(clear_options)
	_clear_directory(CACHE_DIR)

	for use_web_fetch in [true, false]:
		for chunk_size in CHUNK_SIZES:
			await _run_case(url, use_web_fetch, chunk_size)

	print("WEB_BENCH_DONE")


func _run_case(url: String, use_web_fetch: bool, chunk_size: int) -> void:
	var options: PackRatOptions = PackRatOptions.new()
	options.id = "web_bench_%s_%d" % ["fetch" if use_web_fetch else "httprequest", chunk_size]
	options.cache_dir = CACHE_DIR
	options.use_web_fetch = use_web_fetch
	options.download_chunk_size = chunk_size
	options.capture_timings = true
	options.always_download = true

	var started_msec: int = Time.get_ticks_msec()
	var case_url: String = "%s?case=%s_%d_%d" % [url, "fetch" if use_web_fetch else "httprequest", chunk_size, Time.get_ticks_usec()]
	var result: PackRatResult = await PackRat.load_resource_pack(case_url, options)
	var elapsed_msec: int = Time.get_ticks_msec() - started_msec
	var label: String = "fetch" if use_web_fetch else "httprequest"
	print("WEB_BENCH case=%s chunk=%d ok=%s elapsed=%d timings=%s" % [
		label,
		chunk_size,
		str(result.ok),
		elapsed_msec,
		JSON.stringify(result.timings_msec),
	])


func _absolute_pack_url() -> String:
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return PACK_URL

	var origin: String = String(bridge.eval("window.location.origin + window.location.pathname.replace(/[^/]*$/, '')", true))
	if not origin.ends_with("/"):
		origin += "/"
	return origin + PACK_URL


func _clear_directory(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return

	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))

	for directory_name in DirAccess.get_directories_at(path):
		_clear_directory(path.path_join(directory_name))
		DirAccess.remove_absolute(path.path_join(directory_name))
