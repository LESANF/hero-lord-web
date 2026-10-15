extends SceneTree
# Re-encode every PCM AudioStreamWAV .sample in a directory to QOA, in place.
# Same resource type, same mix_rate/stereo/loop points/length, ~5x fewer bytes.
#   godot --headless --script tools/compress_audio.gd -- build/project/.godot/imported


func _init() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	var before := 0
	var after := 0
	var count := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".sample"):
			continue
		var path := dir.path_join(f)
		var s: AudioStreamWAV = ResourceLoader.load(path, "AudioStreamWAV", ResourceLoader.CACHE_MODE_IGNORE)
		if s == null or s.format == AudioStreamWAV.FORMAT_QOA:
			continue
		var tmp := dir.path_join("_compress_audio.wav")
		s.save_to_wav(tmp)
		var q := AudioStreamWAV.load_from_file(tmp, {
			"force/8_bit": false, "force/mono": false, "force/max_rate": false,
			"edit/trim": false, "edit/normalize": false,
			"edit/loop_mode": s.loop_mode + 1, "edit/loop_begin": s.loop_begin, "edit/loop_end": s.loop_end,
			"compress/mode": 2,
		})
		DirAccess.remove_absolute(tmp)
		assert(q.format == AudioStreamWAV.FORMAT_QOA, path)
		assert(q.mix_rate == s.mix_rate and q.stereo == s.stereo, path)
		assert(q.loop_mode == s.loop_mode and q.loop_begin == s.loop_begin and q.loop_end == s.loop_end, path)
		assert(absf(q.get_length() - s.get_length()) < 0.002, path)
		before += FileAccess.get_file_as_bytes(path).size()
		assert(ResourceSaver.save(q, path) == OK, path)
		after += FileAccess.get_file_as_bytes(path).size()
		count += 1
	print("compress_audio: %d samples, %.1f MB -> %.1f MB" % [count, before / 1e6, after / 1e6])
	quit()
