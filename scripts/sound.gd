extends Node
## Sound effects and the crowd. Every file in audio/ is synthesized by
## tools/make_audio.py.
##
## Godot concept: an AudioStreamPlayer plays one sound at a time, so a small
## pool of them lets sounds overlap (the bat's tock and the crowd's cheer).

const SFX_NAMES := ["tock", "edge", "pad", "stumps", "cheer", "roar", "ooh", "groan", "click"]

var _sfx := {}
var _pool: Array[AudioStreamPlayer] = []
var _murmur: AudioStreamPlayer


func _ready() -> void:
	for n in SFX_NAMES:
		_sfx[n] = load("res://audio/sfx/%s.wav" % n)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_murmur = AudioStreamPlayer.new()
	var w: AudioStreamWAV = load("res://audio/loops/murmur.wav")
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(round(w.get_length() * w.mix_rate))
	_murmur.stream = w
	_murmur.volume_db = -16.0
	add_child(_murmur)


func crowd(on: bool) -> void:
	if on and not _murmur.playing:
		_murmur.play()
	elif not on:
		_murmur.stop()


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := _pool[0]
	for c in _pool:
		if not c.playing:
			p = c
			break
	p.stream = _sfx[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
