extends Node
## Sound effects, the crowd and the stadium anthem. Every file in audio/ is
## synthesized by tools/make_audio.py.
##
## Godot concept: an AudioStreamPlayer plays one sound at a time, so a small
## pool of them lets sounds overlap (the bat's tock, the crowd's cheer and
## the trumpet all at once).

const SFX_NAMES := ["tock", "tock_soft", "edge", "pad", "stumps", "helmet", "click", "ooh", "aah",
	"groan", "howzat", "cheer", "roar", "applause", "duck", "sad_trombone", "slide_up", "slide_down",
	"record_scratch", "coo", "four", "six", "win", "ding", "horn", "drum_hit"]

var _sfx := {}
var _pool: Array[AudioStreamPlayer] = []
var _murmur: AudioStreamPlayer
var _music: AudioStreamPlayer


func _ready() -> void:
	for n in SFX_NAMES:
		_sfx[n] = load("res://audio/sfx/%s.wav" % n)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_murmur = _looping("res://audio/loops/murmur.wav", -24.0)   # barely there
	_music = _looping("res://audio/music/stadium.wav", -10.0)


func _looping(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var w: AudioStreamWAV = load(path)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(round(w.get_length() * w.mix_rate))
	p.stream = w
	p.volume_db = db
	add_child(p)
	return p


func crowd(on: bool) -> void:
	if on and not _murmur.playing:
		_murmur.play()
	elif not on:
		_murmur.stop()


func music(on: bool) -> void:
	if on and not _music.playing:
		_music.play()
	elif not on:
		_music.stop()


func play(sound: String, volume_db := 0.0, pitch := 1.0, delay := 0.0) -> void:
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func() -> void: play(sound, volume_db, pitch))
		return
	var p := _pool[0]
	for c in _pool:
		if not c.playing:
			p = c
			break
	p.stream = _sfx[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
