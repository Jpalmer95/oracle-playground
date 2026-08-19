extends Node
## Radio — background music player that streams MP3s from the user's public
## OpenMusic GitHub repo (same source SuperSonic's radio uses). Play/pause,
## next/prev, volume. Downloads tracks with HTTPRequest and plays via
## AudioStreamMP3 (no editor import step needed). State machine is separated
## from I/O so it is headless-testable with an injected queue.

signal track_changed(name: String)
signal playing_changed(playing: bool)

const REPO_API := "https://api.github.com/repos/Jpalmer95/OpenMusic/contents/"

# Built-in fallback queue (title -> raw download URL). Populated so the radio
# works without a network round-trip; fetch_library() refreshes it live.
const BUILTIN_TRACKS := [
	["(Prelude) Interdimensional Song", "https://raw.githubusercontent.com/Jpalmer95/OpenMusic/main/(Prelude)%20Interdimensional%20Song.mp3"],
	["Cyclops Codebreaker", "https://raw.githubusercontent.com/Jpalmer95/OpenMusic/main/Cyclops%20Codebreaker%20-%20Homer%E2%80%99s%20IO-dyssey%20-%20part%202.mp3"],
	["Electro Polymath", "https://raw.githubusercontent.com/Jpalmer95/OpenMusic/main/Electro%20Polymath.mp3"],
	["Future Symphony Phase 1", "https://raw.githubusercontent.com/Jpalmer95/OpenMusic/main/Future%20Symphony%20Phase%201.mp3"],
	["Interdimensional Symphony", "https://raw.githubusercontent.com/Jpalmer95/OpenMusic/main/Interdimensional%20Symphony.mp3"],
	["Pulse of the Nebula", "https://raw.githubusercontent.com/Jpalmer95/OpenMusic/main/Pulse%20of%20the%20Nebula.mp3"],
	["Where The Dance Goes", "https://raw.githubusercontent.com/Jpalmer95/OpenMusic/main/Where%20The%20Dance%20Goes.mp3"],
]

var queue: Array = []           # [{name: String, url: String}]
var index := -1
var playing := false
var volume := 0.5

var _player: AudioStreamPlayer
var _http: HTTPRequest
var _last_url := ""
var no_io := false      # headless tests set this to skip HTTP + audio playback


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = linear_to_db(volume)
	add_child(_player)
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_downloaded)
	# Seed the built-in queue so the radio is usable offline immediately.
	for t in BUILTIN_TRACKS:
		queue.append({"name": t[0], "url": t[1]})


func _exit_tree() -> void:
	if _player:
		_player.stop()


func set_queue(tracks: Array) -> void:
	## Inject a [{name, url}, ...] list (tests, or fetch_library results).
	queue = tracks.duplicate()
	index = -1
	playing = false


func current_name() -> String:
	if index < 0 or index >= queue.size():
		return ""
	return str(queue[index]["name"])


func current_url() -> String:
	if index < 0 or index >= queue.size():
		return ""
	return str(queue[index]["url"])


func has_tracks() -> bool:
	return queue.size() > 0


func toggle() -> void:
	if not has_tracks():
		return
	if index < 0:
		play_index(0)
	elif playing:
		pause()
	else:
		play()


func play() -> void:
	if index < 0:
		play_index(0)
		return
	_start_playback()


func play_index(i: int) -> void:
	if queue.is_empty():
		return
	index = wrapi(i, 0, queue.size())
	_start_playback()


func next() -> void:
	if not has_tracks():
		return
	if index < 0:
		play_index(0)
	else:
		play_index(index + 1)


func prev() -> void:
	if not has_tracks():
		return
	if index < 0:
		play_index(0)
	else:
		play_index(index - 1)


func pause() -> void:
	if _player:
		_player.stream_paused = true
	playing = false
	playing_changed.emit(false)


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	if _player:
		_player.volume_db = linear_to_db(volume)


func volume_linear() -> float:
	return volume


func stop() -> void:
	if _player:
		_player.stop()
	playing = false
	playing_changed.emit(false)


func _start_playback() -> void:
	if _player == null:
		return
	var url := current_url()
	if url == "":
		return
	playing = true
	playing_changed.emit(true)
	track_changed.emit(current_name())
	if no_io:
		return
	if url == _last_url and _player.stream != null:
		_player.stream_paused = false
		_player.play()
		return
	_last_url = url
	# Fetch fresh bytes (cache-hit behavior: still cheap, respects redirects).
	var err := _http.request(url)
	if err != OK:
		push_warning("Radio: request failed (%s)" % err)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# Skip to next track on failure so the radio never deadlocks.
		push_warning("Radio: download failed (result=%d code=%d)" % [result, code])
		playing = false
		next()
		return
	var stream := AudioStreamMP3.new()
	stream.data = body
	stream.loop = false
	if _player:
		_player.stream = stream
		_player.play()
	# Auto-advance when the track ends.
	if not _player.finished.is_connected(_on_finished):
		_player.finished.connect(_on_finished)


func _on_finished() -> void:
	next()