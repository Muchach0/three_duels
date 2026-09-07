extends Node
class_name Combat_Component

@export var max_health := 100.0
@export var max_guard := 100.0
@export var attack_health_damage := 20.0
@export var attack_guard_damage := 35.0
@export var heavy_attack_health_damage := 20.0
@export var heavy_attack_guard_damage := 70.0
@export var dizzy_duration := 2.0

signal attack_started(attack_type: int)
signal attack_finished(attack_type: int)
signal stagger_started
signal stagger_finished
signal defeated

const COMBAT_LAYER_PLAYER_WEAPON := 1 << 1
const COMBAT_LAYER_ENEMY_WEAPON := 1 << 2
const COMBAT_LAYER_PLAYER_HURTBOX := 1 << 3
const COMBAT_LAYER_ENEMY_HURTBOX := 1 << 4

enum AttackType {
	LIGHT,
	HEAVY,
}

var character: Node3D
var hurtbox: Area3D
var weapon_hitbox: Area3D
var weapon_hitbox_shape: CollisionShape3D
var health := 100.0
var guard := 100.0
var is_blocking := false
var is_defeated := false
var is_dizzy := false

var _attack_sequence_id := 0
var _active_attack_id := 0
var _hit_targets_this_swing: Dictionary = {}
var _weapon_hitbox_active := false
var _attack_window_pending := false
var _attack_animation_started := false
var _active_attack_type := AttackType.LIGHT
var _dizzy_time_remaining := 0.0


func setup(owner_character: Node3D, hurtbox_node: Area3D) -> void:
	character = owner_character
	hurtbox = hurtbox_node
	health = maxf(max_health, 0.0)
	guard = maxf(max_guard, 0.0)
	is_defeated = health <= 0.0
	is_blocking = false
	is_dizzy = false
	_dizzy_time_remaining = 0.0
	_hit_targets_this_swing.clear()
	_active_attack_id = 0
	_weapon_hitbox_active = false
	_attack_window_pending = false
	_attack_animation_started = false
	_active_attack_type = AttackType.LIGHT

	character.add_to_group("combat_character")
	if _is_player():
		character.add_to_group("player_character")
	elif _is_enemy():
		character.add_to_group("enemy_character")

	_setup_hurtbox()
	set_weapon_hitbox_active(false)
	emit_combat_stats_changed.call_deferred()


func physics_process(_delta: float) -> void:
	_update_dizzy(_delta)
	_update_attack_window()


func attack(attack_type := AttackType.LIGHT) -> bool:
	if not can_start_attack():
		return false

	character.call("set_attack_filter_for_movement")
	character.call("request_attack_animation", attack_type)
	_start_attack_window(attack_type)
	attack_started.emit(attack_type)
	return true


func can_start_attack() -> bool:
	return _can_start_attack()


func is_attack_in_progress() -> bool:
	return _attack_window_pending


func set_blocking(blocking: bool) -> void:
	blocking = blocking and (_is_player() or _is_enemy()) and not is_defeated and not is_dizzy
	var changed := is_blocking != blocking

	is_blocking = blocking

	if changed and is_blocking:
		cancel_attack()

	if character != null:
		character.call("set_block_animation", is_blocking)


func receive_hit(attacker: Node, hit_data: Dictionary) -> void:
	if not _can_receive_hit(attacker):
		return

	EventBus.combat_hit_detected.emit(attacker, character, hit_data)
	if is_blocking:
		_apply_guard_damage(float(hit_data.get("guard_damage", 0.0)), hit_data)
	else:
		_apply_health_damage(float(hit_data.get("health_damage", 0.0)), hit_data)


func set_weapon_hitbox(hitbox: Area3D) -> void:
	clear_weapon_hitbox()
	if hitbox == null:
		push_warning("Equipped right-hand prop has no WeaponHitbox.")
		return

	weapon_hitbox = hitbox
	_setup_weapon_hitbox()
	set_weapon_hitbox_active(false)


func clear_weapon_hitbox() -> void:
	set_weapon_hitbox_active(false)
	weapon_hitbox = null
	weapon_hitbox_shape = null


func find_weapon_hitbox(node: Node) -> Area3D:
	if node is Area3D and node.name == "WeaponHitbox":
		return node as Area3D

	for child in node.get_children():
		var hitbox := find_weapon_hitbox(child)
		if hitbox != null:
			return hitbox

	return null


func set_weapon_hitbox_active(active: bool) -> void:
	_weapon_hitbox_active = active and (_is_player() or _is_enemy()) and not is_defeated and not is_dizzy
	if weapon_hitbox == null:
		return

	weapon_hitbox.set_deferred("monitoring", _weapon_hitbox_active)
	if weapon_hitbox_shape != null:
		weapon_hitbox_shape.set_deferred("disabled", not _weapon_hitbox_active)

	if _weapon_hitbox_active:
		_process_current_weapon_overlaps()


func open_hitbox() -> void:
	if _attack_window_pending:
		set_weapon_hitbox_active(true)


func close_hitbox() -> void:
	if _attack_window_pending:
		set_weapon_hitbox_active(false)


func emit_combat_stats_changed() -> void:
	EventBus.combat_stats_changed.emit(character, health, max_health, guard, max_guard)


func reset_for_duel() -> void:
	cancel_attack()
	_attack_sequence_id = 0
	_active_attack_id = 0
	_hit_targets_this_swing.clear()
	_weapon_hitbox_active = false
	_attack_window_pending = false
	_attack_animation_started = false
	_active_attack_type = AttackType.LIGHT
	_dizzy_time_remaining = 0.0
	health = maxf(max_health, 0.0)
	guard = maxf(max_guard, 0.0)
	is_defeated = false
	is_blocking = false
	is_dizzy = false
	set_weapon_hitbox_active(false)
	if character != null:
		character.call("clear_combat_inputs")
		character.call("set_block_animation", false)
		character.call("set_dizzy_animation", false)
		character.call("reset_combat_animation")
	emit_combat_stats_changed()


func _setup_hurtbox() -> void:
	if hurtbox == null:
		push_warning("%s has no Hurtbox; combat receive detection is disabled." % character.name)
		return

	hurtbox.set_meta("combat_owner", character)
	hurtbox.add_to_group("combat_hurtbox")
	hurtbox.monitoring = true
	hurtbox.monitorable = true
	hurtbox.collision_layer = COMBAT_LAYER_PLAYER_HURTBOX if _is_player() else COMBAT_LAYER_ENEMY_HURTBOX
	hurtbox.collision_mask = 0


func _setup_weapon_hitbox() -> void:
	if weapon_hitbox == null:
		return

	weapon_hitbox_shape = _find_weapon_hitbox_shape(weapon_hitbox)
	weapon_hitbox.set_meta("combat_owner", character)
	weapon_hitbox.add_to_group("combat_weapon_hitbox")
	weapon_hitbox.monitorable = true
	weapon_hitbox.collision_layer = COMBAT_LAYER_PLAYER_WEAPON if _is_player() else COMBAT_LAYER_ENEMY_WEAPON
	weapon_hitbox.collision_mask = COMBAT_LAYER_ENEMY_HURTBOX if _is_player() else COMBAT_LAYER_PLAYER_HURTBOX
	if not weapon_hitbox.area_entered.is_connected(_on_weapon_hitbox_area_entered):
		weapon_hitbox.area_entered.connect(_on_weapon_hitbox_area_entered)


func _can_start_attack() -> bool:
	if not (_is_player() or _is_enemy()) or is_defeated or is_blocking or is_dizzy:
		return false
	if character == null or not character.has_method("can_play_attack_animation"):
		return false
	return bool(character.call("can_play_attack_animation"))


func _start_attack_window(attack_type: int) -> void:
	_attack_sequence_id += 1
	_active_attack_id = _attack_sequence_id
	_active_attack_type = attack_type
	_hit_targets_this_swing.clear()
	_attack_window_pending = true
	_attack_animation_started = false
	set_weapon_hitbox_active(false)


func _update_attack_window() -> void:
	if not _attack_window_pending:
		return
	if is_defeated or is_dizzy:
		_finish_attack_window()
		return

	if _weapon_hitbox_active:
		_process_current_weapon_overlaps()

	if bool(character.call("is_attack_animation_playing")):
		_attack_animation_started = true
	elif _attack_animation_started:
		_finish_attack_window()


func _finish_attack_window() -> void:
	var finished_attack_type := _active_attack_type
	var had_pending_window := _attack_window_pending
	_attack_window_pending = false
	_attack_animation_started = false
	_active_attack_type = AttackType.LIGHT
	set_weapon_hitbox_active(false)
	if had_pending_window:
		attack_finished.emit(finished_attack_type)


func cancel_attack() -> void:
	if _attack_window_pending:
		_finish_attack_window()

	if character != null:
		character.call("abort_attack_animation")


func _on_weapon_hitbox_area_entered(area: Area3D) -> void:
	_try_apply_weapon_hit(area)


func _try_apply_weapon_hit(area: Area3D) -> void:
	if not _weapon_hitbox_active:
		return

	var defender := _get_character_from_hurtbox(area)
	if defender == null or _hit_targets_this_swing.has(defender.get_instance_id()):
		return
	if not _can_attack(defender):
		return

	_hit_targets_this_swing[defender.get_instance_id()] = true
	defender.call("receive_hit", character, _build_hit_data(defender))


func _process_current_weapon_overlaps() -> void:
	if not _weapon_hitbox_active or weapon_hitbox == null:
		return

	if weapon_hitbox.monitoring:
		for area in weapon_hitbox.get_overlapping_areas():
			_try_apply_weapon_hit(area)

	_process_weapon_shape_query()


func _process_weapon_shape_query() -> void:
	if weapon_hitbox_shape == null or weapon_hitbox_shape.shape == null:
		return

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = weapon_hitbox_shape.shape
	query.transform = weapon_hitbox_shape.global_transform
	query.collision_mask = weapon_hitbox.collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [weapon_hitbox.get_rid()]

	var results := character.get_world_3d().direct_space_state.intersect_shape(query)
	for result in results:
		var collider := result.get("collider") as Area3D
		if collider != null:
			_try_apply_weapon_hit(collider)


func _get_character_from_hurtbox(area: Area3D) -> Node:
	if area == null or not area.is_in_group("combat_hurtbox"):
		return null

	var owner := area.get_meta("combat_owner", null) as Node
	if owner != null and is_instance_valid(owner):
		return owner

	return null


func _can_attack(defender: Node) -> bool:
	if defender == null or defender == character:
		return false
	if not defender.has_method("receive_hit"):
		return false
	if not _is_opposing_character(defender):
		return false
	if defender.has_method("is_defeated") and bool(defender.call("is_defeated")):
		return false
	return true


func _can_receive_hit(attacker: Node) -> bool:
	if is_defeated or attacker == character:
		return false
	if attacker == null:
		return false
	return _is_opposing_character(attacker)


func _build_hit_data(defender: Node) -> Dictionary:
	return {
		"attack_id": _active_attack_id,
		"attack_type": _active_attack_type,
		"health_damage": _get_active_attack_health_damage(),
		"guard_damage": _get_active_attack_guard_damage(),
		"attacker_path": character.get_path(),
		"defender_path": defender.get_path(),
	}


func _get_active_attack_health_damage() -> float:
	if _active_attack_type == AttackType.HEAVY:
		return heavy_attack_health_damage

	return attack_health_damage


func _get_active_attack_guard_damage() -> float:
	if _active_attack_type == AttackType.HEAVY:
		return heavy_attack_guard_damage

	return attack_guard_damage


func _apply_guard_damage(amount: float, hit_data: Dictionary) -> void:
	if amount <= 0.0 or is_defeated or is_dizzy:
		return

	guard = maxf(guard - amount, 0.0)
	EventBus.combat_damage_applied.emit(character, hit_data)
	emit_combat_stats_changed()
	character.call("play_block_impact")

	if guard <= 0.0:
		_enter_dizzy()


func _apply_health_damage(amount: float, hit_data: Dictionary) -> void:
	if amount <= 0.0 or is_defeated:
		return

	health = maxf(health - amount, 0.0)
	EventBus.combat_damage_applied.emit(character, hit_data)
	emit_combat_stats_changed()

	if health <= 0.0 and not is_defeated:
		is_defeated = true
		is_dizzy = false
		_dizzy_time_remaining = 0.0
		set_blocking(false)
		set_weapon_hitbox_active(false)
		character.call("set_dizzy_animation", false)
		character.call("play_death")
		defeated.emit()
		EventBus.combat_character_defeated.emit(character)
	else:
		character.call("play_hit_react")


func _enter_dizzy() -> void:
	if is_defeated or is_dizzy:
		return

	is_dizzy = true
	stagger_started.emit()
	_dizzy_time_remaining = maxf(dizzy_duration, 0.0)
	cancel_attack()
	set_blocking(false)
	set_weapon_hitbox_active(false)

	if character != null:
		character.call("clear_combat_inputs")
		character.call("set_dizzy_animation", true)

	if _dizzy_time_remaining <= 0.0:
		_exit_dizzy()


func _update_dizzy(delta: float) -> void:
	if not is_dizzy:
		return
	if is_defeated:
		is_dizzy = false
		_dizzy_time_remaining = 0.0
		return

	_dizzy_time_remaining -= delta
	if _dizzy_time_remaining <= 0.0:
		_exit_dizzy()


func _exit_dizzy() -> void:
	if not is_dizzy:
		return

	is_dizzy = false
	_dizzy_time_remaining = 0.0
	guard = maxf(max_guard, 0.0)
	emit_combat_stats_changed()

	if character != null:
		character.call("set_dizzy_animation", false)
	stagger_finished.emit()


func _find_weapon_hitbox_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node as CollisionShape3D

	for child in node.get_children():
		var shape := _find_weapon_hitbox_shape(child)
		if shape != null:
			return shape

	return null


func _is_player() -> bool:
	return character != null and character.has_method("is_player_character") and bool(character.call("is_player_character"))


func _is_enemy() -> bool:
	return character != null and character.has_method("is_enemy_character") and bool(character.call("is_enemy_character"))


func _is_opposing_character(other_character: Node) -> bool:
	if _is_player():
		return other_character.has_method("is_enemy_character") and bool(other_character.call("is_enemy_character"))
	if _is_enemy():
		return other_character.has_method("is_player_character") and bool(other_character.call("is_player_character"))
	return false
