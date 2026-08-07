extends Node
## Audio feedback generator for CosmoScope UI interaction and gaze dwelling.
## Synthesizes short audio tones so the application doesn't require external SFX files.

var _audio_player: AudioStreamPlayer

func _ready() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "SFXPlayerNode"
	_audio_player.volume_db = -6.0
	add_child(_audio_player)

## Play a crisp UI click sound.
func play_click() -> void:
	_play_tone(880.0, 0.04)

## Play a planet selection chime.
func play_select() -> void:
	_play_tone(1174.66, 0.12)  # D6 tone

## Play a gaze dwell charging tone.
func play_gaze_tick() -> void:
	_play_tone(659.25, 0.03)  # E5 tone

func _play_tone(freq: float, duration: float) -> void:
	var sample_rate := 44100
	var num_samples := int(sample_rate * duration)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate

	var data := PackedByteArray()
	data.resize(num_samples)
	for i in num_samples:
		var t := float(i) / float(sample_rate)
		var val := sin(TAU * freq * t)
		var envelope := 1.0 - (float(i) / float(num_samples))
		data[i] = int(clampf(128.0 + 127.0 * val * envelope, 0.0, 255.0))

	stream.data = data
	_audio_player.stream = stream
	_audio_player.play()
