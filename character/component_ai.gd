extends Node
class_name AiComponent

signal state_changed(character: Node, state_name: String)

enum State {
	IDLE,
	APPROACH_PLAYER,
	ATTACK,
	BLOCK,
	RECOVER,
	STAGGER,
	DEATH,
}

@export var ai_enabled := true

var profile: EnemyAiProfile
var _character: CharacterBody3D
var _combat: Combat_Component
var _state := State.IDLE
var _target: Node3D
var _state_time_remaining := 0.0
var _attack_decision_time_remaining := 0.0
var _target_lost_time_remaining := 0.0
var _block_time_remaining := 0.0
var _combo_count := 0
var _attack_finished := false
var _block_active := false
var _previous_player_attack_playing := false
var _rng := RandomNumberGenerator.new()
var _debug_override: Variant = null


func setup(owner_character: CharacterBody3D, owner_combat: Combat_Component, owner_profile: EnemyAiProfile) -> void:
	_character = owner_character
	_combat = owner_combat
	profile = owner_profile
	if not _character.is_enemy_character():
		push_warning("AiComponent can only be set up on an enemy character.")
		ai_enabled = false
		return
	if profile == null:
		profile = EnemyAiProfile.new()
		push_warning("Enemy '%s' has no AI profile; using default values." % _character.name)
	_rng.randomize()
	_attack_decision_time_remaining = profile.get_attack_decision_delay()
	_combat.attack_finished.connect(_on_attack_finished)
	_connect_debug_signals()
	_transition_to(State.IDLE, true)


func physics_process(delta: float) -> void:
	if not ai_enabled or _character == null or _combat == null:
		return
	if _combat.is_defeated:
		_transition_to(State.DEATH)
		return
	if _combat.is_dizzy:
		_transition_to(State.STAGGER)
		return
	if _state == State.DEATH:
		return

	_update_target(delta)
	_update_player_attack_edge()
	if _debug_override != null:
		_update_debug_override(delta)
		return

	match _state:
		State.IDLE:
			_update_idle()
		State.APPROACH_PLAYER:
			_update_approach()
		State.ATTACK:
			_update_attack(delta)
		State.BLOCK:
			_update_block(delta)
		State.RECOVER:
			_update_recover(delta)
		State.STAGGER:
			if not _combat.is_dizzy:
				_transition_to(State.RECOVER)


func get_current_state() -> State:
	return _state


func get_current_state_name() -> String:
	return State.keys()[_state].capitalize().replace("_", " ")


func get_target() -> Node3D:
	return _target


func force_debug_state(state: State) -> void:
	_debug_override = state
	_transition_to(state, true)


func clear_debug_override() -> void:
	_debug_override = null
	if _state != State.DEATH and _state != State.STAGGER:
		_transition_to(State.IDLE, true)


func _exit_tree() -> void:
	_disconnect_debug_signals()


func _connect_debug_signals() -> void:
	EventBus.ui_test_enemy_idle.connect(_on_debug_idle_requested)
	EventBus.ui_test_enemy_attack.connect(_on_debug_attack_requested)
	EventBus.ui_test_enemy_block.connect(_on_debug_block_requested)
	EventBus.ui_test_enemy_clear_override.connect(_on_debug_clear_requested)


func _disconnect_debug_signals() -> void:
	if EventBus.ui_test_enemy_idle.is_connected(_on_debug_idle_requested):
		EventBus.ui_test_enemy_idle.disconnect(_on_debug_idle_requested)
	if EventBus.ui_test_enemy_attack.is_connected(_on_debug_attack_requested):
		EventBus.ui_test_enemy_attack.disconnect(_on_debug_attack_requested)
	if EventBus.ui_test_enemy_block.is_connected(_on_debug_block_requested):
		EventBus.ui_test_enemy_block.disconnect(_on_debug_block_requested)
	if EventBus.ui_test_enemy_clear_override.is_connected(_on_debug_clear_requested):
		EventBus.ui_test_enemy_clear_override.disconnect(_on_debug_clear_requested)


func _on_debug_idle_requested() -> void:
	force_debug_state(State.IDLE)


func _on_debug_attack_requested() -> void:
	force_debug_state(State.ATTACK)


func _on_debug_block_requested() -> void:
	force_debug_state(State.BLOCK)


func _on_debug_clear_requested() -> void:
	clear_debug_override()


func _update_debug_override(delta: float) -> void:
	match _debug_override:
		State.IDLE:
			_character.clear_ai_movement()
			_combat.set_blocking(false)
			_face_target()
		State.ATTACK:
			_update_attack(delta)
		State.BLOCK:
			_character.clear_ai_movement()
			_face_target()
			_combat.set_blocking(true)


func _update_target(delta: float) -> void:
	var candidate := _find_player()
	if candidate != null and _distance_to(candidate) <= profile.perception_radius:
		_target = candidate
		_target_lost_time_remaining = profile.target_loss_grace_period
		return
	if _target != null:
		_target_lost_time_remaining -= delta
		if _target_lost_time_remaining > 0.0:
			return
	_target = null


func _find_player() -> Node3D:
	for candidate in get_tree().get_nodes_in_group("player_character"):
		if candidate is Node3D and is_instance_valid(candidate) and not candidate.is_defeated():
			return candidate as Node3D
	return null


func _update_player_attack_edge() -> void:
	var is_playing: bool = _target != null and _target.is_attack_animation_playing()
	var attack_started: bool = is_playing and not _previous_player_attack_playing
	_previous_player_attack_playing = is_playing
	if not attack_started or (_state != State.IDLE and _state != State.APPROACH_PLAYER):
		return
	if _distance_to(_target) <= profile.reaction_range and _rng.randf() < profile.get_block_probability():
		_transition_to(State.BLOCK)


func _update_idle() -> void:
	_character.clear_ai_movement()
	_combat.set_blocking(false)
	if _target == null:
		return
	_face_target()
	if _distance_to(_target) > profile.attack_range:
		_transition_to(State.APPROACH_PLAYER)
	else:
		_update_attack_decision_timer(get_physics_process_delta_time())


func _update_approach() -> void:
	_combat.set_blocking(false)
	if _target == null:
		_transition_to(State.IDLE)
		return
	_face_target()
	if _distance_to(_target) > profile.attack_range:
		_character.set_ai_movement(_flat_direction_to(_target.global_position), profile.approach_running)
		return
	_character.clear_ai_movement()
	_update_attack_decision_timer(get_physics_process_delta_time())


func _update_attack(delta: float) -> void:
	_character.clear_ai_movement()
	_face_target()
	if _combat.is_attack_in_progress():
		return
	if _attack_finished:
		_attack_finished = false
		if _combo_count < profile.max_combo_length and _target != null and _distance_to(_target) <= profile.attack_range and _rng.randf() < profile.combo_probability:
			_combo_count += 1
			_attack_decision_time_remaining = profile.get_attack_decision_delay()
			return
		_transition_to(State.RECOVER)
		return
	_attack_decision_time_remaining = maxf(_attack_decision_time_remaining - delta, 0.0)
	if _attack_decision_time_remaining <= 0.0:
		if not _combat.attack(profile.choose_attack_type(_rng)):
			_transition_to(State.APPROACH_PLAYER if _target != null else State.IDLE)


func _update_block(delta: float) -> void:
	_character.clear_ai_movement()
	_face_target()
	if not _block_active:
		_state_time_remaining = maxf(_state_time_remaining - delta, 0.0)
		if _state_time_remaining <= 0.0:
			_block_active = true
			_combat.set_blocking(true)
		return
	_block_time_remaining = maxf(_block_time_remaining - delta, 0.0)
	if _block_time_remaining <= 0.0:
		_transition_to(State.RECOVER)


func _update_recover(delta: float) -> void:
	_character.clear_ai_movement()
	_combat.set_blocking(false)
	_face_target()
	_state_time_remaining = maxf(_state_time_remaining - delta, 0.0)
	if _state_time_remaining > 0.0:
		return
	_attack_decision_time_remaining = profile.get_attack_decision_delay()
	_transition_to(State.APPROACH_PLAYER if _target != null and _distance_to(_target) > profile.attack_range else State.IDLE)


func _try_start_attack_or_wait() -> void:
	_attack_decision_time_remaining = profile.get_attack_decision_delay()
	if _rng.randf() < profile.get_aggression_probability():
		_transition_to(State.ATTACK)


func _update_attack_decision_timer(delta: float) -> void:
	_attack_decision_time_remaining = maxf(_attack_decision_time_remaining - delta, 0.0)
	if _attack_decision_time_remaining <= 0.0:
		_try_start_attack_or_wait()


func _transition_to(next_state: State, reset := false) -> void:
	if _state == State.DEATH and next_state != State.DEATH:
		return
	if _state == next_state and not reset:
		return
	if _state == State.BLOCK:
		_combat.set_blocking(false)
	_state = next_state
	_state_time_remaining = 0.0
	_block_time_remaining = 0.0
	_block_active = false
	match _state:
		State.IDLE, State.APPROACH_PLAYER:
			_character.clear_ai_movement()
			_combat.set_blocking(false)
		State.ATTACK:
			_character.clear_ai_movement()
			_combat.set_blocking(false)
			_combo_count = 1
			_attack_finished = false
			_attack_decision_time_remaining = 0.0
		State.BLOCK:
			_character.clear_ai_movement()
			_state_time_remaining = profile.block_reaction_delay
			_block_time_remaining = profile.block_duration
		State.RECOVER:
			_character.clear_ai_movement()
			_combat.set_blocking(false)
			_state_time_remaining = profile.get_opening_duration()
		State.STAGGER:
			_character.clear_ai_movement()
			_combat.set_blocking(false)
			_combat.cancel_attack()
		State.DEATH:
			_character.clear_ai_movement()
			_combat.set_blocking(false)
			_combat.cancel_attack()
			_state_time_remaining = 0.0
			_attack_decision_time_remaining = 0.0
			_target_lost_time_remaining = 0.0
			_debug_override = null
	state_changed.emit(_character, get_current_state_name())


func _on_attack_finished(_attack_type: int) -> void:
	_attack_finished = true


func _face_target() -> void:
	if _target != null:
		_character.face_ai_target(_target.global_position)


func _flat_direction_to(world_position: Vector3) -> Vector3:
	var direction := world_position - _character.global_position
	direction.y = 0.0
	return direction.normalized()


func _distance_to(node: Node3D) -> float:
	var offset := node.global_position - _character.global_position
	offset.y = 0.0
	return offset.length()
