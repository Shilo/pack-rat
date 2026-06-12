extends Control

const CACHE_DIR: String = "user://pack_rat_web_download_benchmark_cache"
const PACK_URL: String = "packs/packrat-demo-gallery.zip"
const SAMPLE_COUNT: int = 5
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

	var summaries: Dictionary = {}
	for use_web_fetch in [true, false]:
		for chunk_size in CHUNK_SIZES:
			for sample_index in range(SAMPLE_COUNT):
				var metrics: Dictionary = await _run_case(url, use_web_fetch, chunk_size, sample_index + 1)
				var summary_key: String = "%s_%d" % [str(metrics.get("case", "")), chunk_size]
				if not summaries.has(summary_key):
					summaries[summary_key] = []
				var samples: Array = summaries[summary_key]
				samples.append(metrics)
				summaries[summary_key] = samples
				await get_tree().process_frame

	_print_summaries(summaries)

	print("WEB_BENCH_DONE")


func _run_case(url: String, use_web_fetch: bool, chunk_size: int, sample_index: int) -> Dictionary:
	var options: PackRatOptions = PackRatOptions.new()
	options.id = "web_bench_%s_%d" % ["fetch" if use_web_fetch else "httprequest", chunk_size]
	options.cache_dir = CACHE_DIR
	options.use_web_fetch = use_web_fetch
	options.download_chunk_size = chunk_size
	options.capture_timings = true
	options.always_download = true

	var started_msec: int = Time.get_ticks_msec()
	var label: String = "fetch" if use_web_fetch else "httprequest"
	var case_url: String = "%s?case=%s_%d_%d_%d" % [url, label, chunk_size, sample_index, Time.get_ticks_usec()]
	var result: PackRatResult = await PackRat.load_resource_pack(case_url, options)
	var elapsed_msec: int = Time.get_ticks_msec() - started_msec
	var transfer_msec: int = int(result.timings_msec.get("download_http_transfer_msec", -1))
	var write_chunks: int = int(result.timings_msec.get("download_http_write_chunks", 0))
	var write_max_chunk_size: int = int(result.timings_msec.get("download_http_write_max_chunk_size", 0))
	print("WEB_BENCH sample=%d case=%s chunk=%d ok=%s elapsed=%d transfer=%d write_chunks=%d write_max_chunk=%d timings=%s" % [
		sample_index,
		label,
		chunk_size,
		str(result.ok),
		elapsed_msec,
		transfer_msec,
		write_chunks,
		write_max_chunk_size,
		JSON.stringify(result.timings_msec),
	])
	return {
		"case": label,
		"chunk": chunk_size,
		"ok": result.ok,
		"elapsed": elapsed_msec,
		"transfer": transfer_msec,
		"write_chunks": write_chunks,
		"write_max_chunk": write_max_chunk_size,
	}


func _print_summaries(summaries: Dictionary) -> void:
	for key in summaries.keys():
		var samples: Array = summaries[key]
		var ok_count: int = 0
		var elapsed_sum: int = 0
		var transfer_sum: int = 0
		var max_write_chunk: int = 0
		for sample in samples:
			if bool(sample.get("ok", false)):
				ok_count += 1
			elapsed_sum += int(sample.get("elapsed", 0))
			transfer_sum += maxi(0, int(sample.get("transfer", 0)))
			max_write_chunk = maxi(max_write_chunk, int(sample.get("write_max_chunk", 0)))

		var count: int = maxi(1, samples.size())
		print("WEB_BENCH_SUMMARY key=%s samples=%d ok=%d avg_elapsed=%d avg_transfer=%d max_write_chunk=%d" % [
			key,
			samples.size(),
			ok_count,
			roundi(float(elapsed_sum) / float(count)),
			roundi(float(transfer_sum) / float(count)),
			max_write_chunk,
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
