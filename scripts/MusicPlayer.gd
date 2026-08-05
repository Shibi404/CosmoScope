extends AudioStreamPlayer
## Looping background music, autoloaded so it persists across scene changes
## (menu -> VR -> AR) without restarting or gapping.
##
## Drop a royalty-free track at one of the candidate paths below and it plays
## automatically on load. OGG is best for seamless looping. With no file
## present the app simply runs silently (no error).

const CANDIDATES := [
	"res://assets/audio/theme.ogg",
	"res://assets/audio/theme.mp3",
	"res://assets/audio/theme.wav",
]

@export var music_volume_db: float = -12.0

func _ready() -> void:
	volume_db = music_volume_db
	var path := _find_track()
	if path.is_empty():
		push_warning("MusicPlayer: no track found. Add res://assets/audio/theme.ogg to enable music.")
		return
	stream = load(path)
	_enable_loop(stream)
	play()

func _find_track() -> String:
	for p in CANDIDATES:
		if ResourceLoader.exists(p):
			return p
	return ""

# Force looping regardless of the file's import setting.
func _enable_loop(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis or s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
