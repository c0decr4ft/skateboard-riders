extends Node
## Three-song skate playlist. The autoload keeps the playhead across builder and ride.

var player: AudioStreamPlayer
var songs: Array[AudioStreamMP3] = []
var index: int = 0
var gap: float = 0.0
var waiting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	player = AudioStreamPlayer.new()
	player.name = "SkateLoop"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.volume_db = -12.0
	player.finished.connect(_on_song_finished)
	add_child(player)
	_add_song("res://audio/blesksound-skate.mp3")
	_add_song("res://audio/extreme-extreme-bike-skate.mp3")
	_add_song("res://audio/extreme-bike-skate.mp3")
	_play_current()


func _add_song(path: String) -> void:
	var loaded: Resource = load(path)
	var mp3: AudioStreamMP3 = loaded as AudioStreamMP3
	if mp3 == null:
		push_error("Missing skate music %s" % path)
		return
	mp3.loop = false
	songs.append(mp3)


func _process(delta: float) -> void:
	if not waiting:
		return
	gap += delta
	if gap < 1.0:
		return
	waiting = false
	_play_current()


func _play_current() -> void:
	if songs.is_empty() or player == null:
		return
	player.stream = songs[index]
	player.play()


func _on_song_finished() -> void:
	if songs.is_empty() or waiting:
		return
	index = (index + 1) % songs.size()
	gap = 0.0
	waiting = true
