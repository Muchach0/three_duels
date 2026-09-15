extends Node
## Non-spatial audio. Playback stays on Godot's platform default (Sample on Web).
## Separate bounded pools let menu confirmations survive scene changes and keep
## footsteps/combat from cutting off result stingers or ambience.

enum Cue {
    SWING_LIGHT, SWING_HEAVY, HIT_LIGHT, HIT_HEAVY, BLOCK, DEFENSE_BREAK,
    DODGE, BODY_FALL, FOOTSTEP, UI_HOVER, UI_CONFIRM, EQUIP,
    DUEL_START, DUEL_WIN, RUN_VICTORY, RUN_DEFEAT,
}

enum Music { MENU, COMBAT }

const MUSIC := {
    Music.MENU: preload("res://assets/sounds/menu_music.mp3"),
    Music.COMBAT: preload("res://assets/sounds/combat_music.mp3"),
}
const MUSIC_LEVELS := {Music.MENU: -20.0, Music.COMBAT: -24.0}

# stream, volume_db, pitch variation, source start offset in seconds.
# Footstep's audible boot contact begins at ~0.30 s in the supplied recording.
const SOUNDS := {
    Cue.SWING_LIGHT: [preload("res://assets/sounds/sword_swing_light_1.wav"), -12.0, 0.00, 0.0],
    Cue.SWING_HEAVY: [preload("res://assets/sounds/sword_swing_heavy_1.wav"), -10.0, 0.00, 0.0],
    Cue.HIT_LIGHT: [preload("res://assets/sounds/hit_light_2.wav"), -9.0, 0.00, 0.0],
    Cue.HIT_HEAVY: [preload("res://assets/sounds/hit_2.wav"), -7.0, 0.00, 0.0],
    Cue.BLOCK: [preload("res://assets/sounds/hit_blocked_1.mp3"), -12.0, 0.04, 0.0],
    Cue.DEFENSE_BREAK: [preload("res://assets/sounds/defensive_stance_break.wav"), -10.0, 0.0, 0.0],
    Cue.DODGE: [preload("res://assets/sounds/dodge.wav"), -14.0, 0.04, 0.0],
    Cue.BODY_FALL: [preload("res://assets/sounds/body_fall.wav"), -12.0, 0.02, 0.0],
    Cue.FOOTSTEP: [preload("res://assets/sounds/footstep_walk.wav"), -20.0, 0.06, 0.28],
    Cue.UI_HOVER: [preload("res://assets/sounds/ui_hover.wav"), -23.0, 0.0, 0.0],
    Cue.UI_CONFIRM: [preload("res://assets/sounds/ui_confirm.wav"), -16.0, 0.0, 0.0],
    Cue.EQUIP: [preload("res://assets/sounds/equipment_equip.wav"), -12.0, 0.0, 0.0],
    Cue.DUEL_START: [preload("res://assets/sounds/duel_start.wav"), -12.0, 0.0, 0.0],
    Cue.DUEL_WIN: [preload("res://assets/sounds/duel_win.wav"), -12.0, 0.0, 0.0],
    Cue.RUN_VICTORY: [preload("res://assets/sounds/run_victory.mp3"), -10.0, 0.0, 0.0],
    Cue.RUN_DEFEAT: [preload("res://assets/sounds/run_defeat.wav"), -12.0, 0.0, 0.0],
}
const AMBIENCE := [
    preload("res://assets/sounds/arena_ambience_loop.wav"),
    preload("res://assets/sounds/flags_loop.wav"),
]
const AMBIENCE_LEVELS := [-26.0, -32.0]
const SFX_VOICES := 12
const UI_VOICES := 4

var _sfx: Array[AudioStreamPlayer] = []
var _ui: Array[AudioStreamPlayer] = []
var _ambience: Array[AudioStreamPlayer] = []
var _stinger: AudioStreamPlayer
var _music: AudioStreamPlayer
var _next_sfx := 0
var _next_ui := 0
var _last_hover_msec := -1000
var _has_interacted := false


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    for index in SFX_VOICES:
        _sfx.append(_make_player("SFX%d" % index))
    for index in UI_VOICES:
        _ui.append(_make_player("UI%d" % index))
    _stinger = _make_player("Stinger")
    _music = _make_player("Music")
    for index in AMBIENCE.size():
        var player := _make_player("Ambience%d" % index)
        player.stream = AMBIENCE[index]
        player.volume_db = AMBIENCE_LEVELS[index]
        _ambience.append(player)
    EventBus.combat_hit_resolved.connect(_on_hit_resolved)
    EventBus.combat_character_defeated.connect(_on_character_defeated)


func _input(event: InputEvent) -> void:
    if event.is_pressed():
        _has_interacted = true


func _make_player(node_name: String) -> AudioStreamPlayer:
    var player := AudioStreamPlayer.new()
    player.name = node_name
    add_child(player)
    return player


func play(cue: Cue, volume_offset := 0.0, pitch := 1.0) -> void:
    var is_ui := cue in [Cue.UI_HOVER, Cue.UI_CONFIRM, Cue.EQUIP]
    var pool := _ui if is_ui else _sfx
    var next := _next_ui if is_ui else _next_sfx
    var voice := pool[next]
    # Reuse an idle voice first; steal in round-robin order only at the cap.
    for candidate in pool:
        if not candidate.playing:
            voice = candidate
            break
    if is_ui:
        _next_ui = (next + 1) % pool.size()
    else:
        _next_sfx = (next + 1) % pool.size()
    _play_on(voice, cue, volume_offset, pitch)


func _play_on(player: AudioStreamPlayer, cue: Cue, volume_offset := 0.0, pitch := 1.0) -> void:
    var sound: Array = SOUNDS[cue]
    player.stop()
    player.stream = sound[0]
    player.volume_db = sound[1] + volume_offset
    player.pitch_scale = pitch * randf_range(1.0 - sound[2], 1.0 + sound[2])
    player.play(sound[3])


func play_stinger(cue: Cue) -> void:
    _play_on(_stinger, cue)


func play_music(track: Music) -> void:
    var stream: AudioStream = MUSIC[track]
    if _music.stream == stream and _music.playing:
        return
    _music.stop()
    _music.stream = stream
    _music.volume_db = MUSIC_LEVELS[track]
    _music.play()


func stop_music() -> void:
    _music.stop()


func set_arena_ambience(enabled: bool) -> void:
    for player in _ambience:
        if enabled and not player.playing:
            player.play()
        elif not enabled:
            player.stop()


func clear_world_audio(keep_music := false) -> void:
    for player in _sfx:
        player.stop()
    _stinger.stop()
    if not keep_music:
        stop_music()
    set_arena_ambience(false)


func connect_character(combat: Combat_Component) -> void:
    if not combat.attack_swing.is_connected(_on_attack_swing):
        combat.attack_swing.connect(_on_attack_swing)
        combat.dodge_started.connect(_on_dodge_started)


func _on_attack_swing(attack_type: int) -> void:
    play(Cue.SWING_HEAVY if attack_type == Combat_Component.AttackType.HEAVY else Cue.SWING_LIGHT)


func _on_dodge_started(_direction: int) -> void:
    play(Cue.DODGE)


func _on_hit_resolved(_defender: Node3D, result: Dictionary) -> void:
    if result.blocked:
        play(Cue.BLOCK)
    if result.health_lost > 0.0:
        play(Cue.HIT_HEAVY if result.attack_type == Combat_Component.AttackType.HEAVY else Cue.HIT_LIGHT)
    if result.defense_broken:
        play(Cue.DEFENSE_BREAK)


func _on_character_defeated(_character: Node) -> void:
    pass
    # play(Cue.BODY_FALL)


func connect_buttons(root: Node) -> void:
    if root is BaseButton:
        var hover := _on_button_hover.bind(root)
        if not root.mouse_entered.is_connected(hover):
            root.mouse_entered.connect(hover)
            root.focus_entered.connect(_on_button_focus.bind(root))
            root.pressed.connect(_on_button_pressed)
    for child in root.get_children():
        connect_buttons(child)


func _on_button_hover(button: BaseButton) -> void:
    # Mouse hover works immediately; debounce duplicate focus + mouse notifications.
    if button.disabled or not button.is_visible_in_tree():
        return
    var now := Time.get_ticks_msec()
    if now - _last_hover_msec < 80:
        return
    _last_hover_msec = now
    play(Cue.UI_HOVER)


func _on_button_focus(button: BaseButton) -> void:
    # Automatic initial focus stays silent; keyboard navigation uses the hover cue.
    if _has_interacted:
        _on_button_hover(button)


func _on_button_pressed() -> void:
    # Button handlers can disable themselves before this callback is delivered.
    play(Cue.UI_CONFIRM)
