extends Node
class_name Combat_Component

@export var max_health := 100.0
## Enemy guard capacity. Player-mode characters use max_stamina instead.
@export var max_guard := 100.0
@export var attack_health_damage := 20.0
@export var attack_guard_damage := 35.0
@export var heavy_attack_health_damage := 35.0
@export var heavy_attack_guard_damage := 70.0
@export var dizzy_duration := 2.0

@export_group("Player Stamina")
@export_range(0.0, 1000.0, 1.0, "or_greater") var max_stamina := 100.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var block_stamina_cost := 20.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var dodge_stamina_cost := 20.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var heavy_attack_stamina_cost := 20.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var stamina_regen_per_second := 5.0

signal attack_started(attack_type: int)
signal attack_finished(attack_type: int)
signal stagger_started
signal stagger_finished
signal dodge_started(direction: int)
signal dodge_finished(direction: int, interrupted: bool)
signal defeated

const COMBAT_LAYER_PLAYER_WEAPON := 1 << 1
const COMBAT_LAYER_ENEMY_WEAPON := 1 << 2
const COMBAT_LAYER_PLAYER_HURTBOX := 1 << 3
const COMBAT_LAYER_ENEMY_HURTBOX := 1 << 4

enum DodgeDirection { FORWARD, BACKWARD, LEFT, RIGHT }

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
var stamina := 100.0
var is_active := true
var _stamina_regen_elapsed := 0.0
var is_blocking := false
var is_defeated := false
var is_dizzy := false
var is_dodging := false
var is_invulnerable := false
var _dodge_direction := DodgeDirection.BACKWARD
var _dodge_animation_started := false
var _dodge_elapsed := 0.0
var _dodge_timeout := 0.0

var _attack_sequence_id := 0
var _active_attack_id := 0
var _hit_targets_this_swing: Dictionary = {}
var _weapon_hitbox_active := false
var _attack_window_pending := false
var _attack_animation_started := false
var _active_attack_type := AttackType.LIGHT
var _dizzy_time_remaining := 0.0


func setup(owner_character: Node3D, hurtbox_node: Area3D) -> void:
	cancel_dodge()
	character = owner_character
	hurtbox = hurtbox_node
	is_active = true
	health = maxf(max_health, 0.0)
	guard = maxf(max_guard, 0.0)
	stamina = maxf(max_stamina, 0.0)
	_stamina_regen_elapsed = 0.0
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


func physics_process(delta: float) -> void:
	if not is_active:
		return
	# Count eligibility before completing actions: their last frame is still busy.
	_update_stamina(delta)
	_update_dizzy(delta)
	_update_attack_window()
	_update_dodge(delta)


func attack(attack_type := AttackType.LIGHT) -> bool:
	if not can_start_attack(attack_type):
		return false

	character.call("set_attack_filter_for_movement")
	character.call("request_attack_animation", attack_type)
	_start_attack_window(attack_type)
	if attack_type == AttackType.HEAVY:
		_spend_stamina(heavy_attack_stamina_cost)
	attack_started.emit(attack_type)
	return true


func can_start_attack(attack_type := AttackType.LIGHT) -> bool:
	if attack_type not in AttackType.values():
		return false
	if not is_active or not (_is_player() or _is_enemy()) or is_defeated or is_blocking or is_dizzy or is_dodging or _attack_window_pending:
		return false
	if attack_type == AttackType.HEAVY and not _can_afford_stamina(heavy_attack_stamina_cost):
		return false
	return bool(character.call("can_play_attack_animation"))


func is_attack_in_progress() -> bool:
	return _attack_window_pending


func set_blocking(blocking: bool) -> void:
	blocking = blocking and is_active and (_is_player() or _is_enemy()) and not is_defeated and not is_dizzy and not is_dodging
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
	var previous_health := health
	var previous_defense := get_defense()
	var blocked := is_blocking
	var defense_broken := false
	# Snapshot spatial context before reactions/defeat listeners run.
	var result := {
		"position": character.global_position,
		"attacker_position": (attacker as Node3D).global_position,
		"attack_type": int(hit_data.get("attack_type", AttackType.LIGHT)),
	}
	var health_damage := maxf(float(hit_data.get("health_damage", 0.0)), 0.0)
	if blocked:
		var cost := _get_block_cost(block_stamina_cost if _is_player() else float(hit_data.get("guard_damage", 0.0)))
		health_damage = _absorb_blocked_hit(health_damage, cost)
		defense_broken = cost > 0.0 and get_defense() <= 0.0
	var helmet: CharacterPropDefinition = character.call("get_equipped_prop_definition", "head")
	if helmet != null:
		health_damage = maxf(health_damage - helmet.armor_value, 0.0)
	_apply_health_damage(health_damage, not blocked)
	if defense_broken:
		_enter_dizzy()
	result["health_lost"] = previous_health - health
	result["blocked"] = blocked
	result["defense_broken"] = defense_broken
	EventBus.combat_hit_resolved.emit(character, result)
	if health != previous_health or get_defense() != previous_defense:
		EventBus.combat_damage_applied.emit(character, hit_data)
		emit_combat_stats_changed()


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
	_weapon_hitbox_active = active and is_active and (_is_player() or _is_enemy()) and not is_defeated and not is_dizzy and not is_dodging
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
	EventBus.combat_stats_changed.emit(character, health, max_health, get_defense(), get_max_defense())


func get_defense() -> float:
	return stamina if _is_player() else guard


func get_max_defense() -> float:
	return max_stamina if _is_player() else max_guard


func reset_for_duel() -> void:
	is_active = true
	cancel_dodge()
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
	stamina = maxf(max_stamina, 0.0)
	_stamina_regen_elapsed = 0.0
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


## Stop gameplay at the finishing blow while the character's AnimationTree keeps playing.
func finish_duel() -> void:
	is_active = false
	cancel_attack()
	cancel_dodge()
	set_blocking(false)
	set_weapon_hitbox_active(false)


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
	if not is_active or is_defeated or is_invulnerable or attacker == character:
		return false
	if not is_instance_valid(attacker) or not attacker is Node3D:
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
	var base_damage := heavy_attack_health_damage if _active_attack_type == AttackType.HEAVY else attack_health_damage
	var weapon: CharacterPropDefinition = character.call("get_equipped_prop_definition", "right_hand")
	return base_damage + (weapon.damage_bonus if weapon != null else 0.0)


func _get_active_attack_guard_damage() -> float:
	if _active_attack_type == AttackType.HEAVY:
		return heavy_attack_guard_damage

	return attack_guard_damage


func _get_block_cost(base_cost: float) -> float:
	# An explicitly free block stays free; equipment cannot make a paid block free.
	if base_cost <= 0.0:
		return 0.0
	var shield: CharacterPropDefinition = character.call("get_equipped_prop_definition", "left_hand")
	return maxf(base_cost - (shield.block_value if shield != null else 0.0), 1.0)


func _absorb_blocked_hit(health_damage: float, cost: float) -> float:
	if cost <= 0.0:
		return 0.0
	var damage_through := 0.0
	if _is_player():
		var paid := minf(stamina, cost)
		stamina -= paid
		damage_through = health_damage * (1.0 - paid / cost)
	else:
		guard = maxf(guard - cost, 0.0)
	character.call("play_block_impact")
	return damage_through


func _apply_health_damage(amount: float, hit_reaction := true) -> void:
	if amount <= 0.0 or is_defeated:
		return

	cancel_dodge()
	health = maxf(health - amount, 0.0)

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
	elif hit_reaction:
		character.call("play_hit_react")


func _enter_dizzy() -> void:
	if is_defeated or is_dizzy:
		return

	cancel_dodge()
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
	if _is_enemy():
		guard = maxf(max_guard, 0.0)
		emit_combat_stats_changed()

	if character != null:
		character.call("set_dizzy_animation", false)
	stagger_finished.emit()


func _can_afford_stamina(amount: float) -> bool:
	return not _is_player() or stamina >= maxf(amount, 0.0)


func _spend_stamina(amount: float) -> void:
	if _is_player() and amount > 0.0:
		stamina = maxf(stamina - amount, 0.0)
		emit_combat_stats_changed()


func _update_stamina(delta: float) -> void:
	if not _is_player() or is_defeated:
		return
	if stamina >= maxf(max_stamina, 0.0):
		_stamina_regen_elapsed = 0.0
		return
	if is_blocking or _attack_window_pending or is_dodging or stamina_regen_per_second <= 0.0:
		return
	_stamina_regen_elapsed += delta
	# Tolerate floating-point accumulation at exact one-second boundaries.
	var ticks := floori(_stamina_regen_elapsed + 1e-9)
	if ticks < 1:
		return
	_stamina_regen_elapsed = maxf(_stamina_regen_elapsed - ticks, 0.0)
	stamina = minf(stamina + ticks * stamina_regen_per_second, maxf(max_stamina, 0.0))
	if stamina >= maxf(max_stamina, 0.0):
		_stamina_regen_elapsed = 0.0
	emit_combat_stats_changed()


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


func can_start_dodge() -> bool:
	if not is_active or not (_is_player() or _is_enemy()) or is_defeated or is_dizzy or is_dodging:
		return false
	if _attack_window_pending or not character.is_on_floor():
		return false
	if not _can_afford_stamina(dodge_stamina_cost):
		return false
	return character.can_play_dodge_animation()


func start_dodge(direction: DodgeDirection) -> bool:
	if direction not in DodgeDirection.values() or not can_start_dodge():
		return false
	var was_blocking := is_blocking
	set_blocking(false)
	is_dodging = true
	is_invulnerable = false
	_dodge_direction = direction
	_dodge_animation_started = false
	_dodge_elapsed = 0.0
	_dodge_timeout = character.dodge_duration + 0.5
	if not character.request_dodge_animation(direction):
		is_dodging = false
		_dodge_timeout = 0.0
		_dodge_direction = DodgeDirection.BACKWARD
		character.stop_dodge_motion_and_visuals()
		set_blocking(was_blocking)
		return false
	_spend_stamina(dodge_stamina_cost)
	dodge_started.emit(direction)
	return true


func cancel_dodge(interrupted := true) -> void:
	is_invulnerable = false
	if not is_dodging:
		return
	var direction := _dodge_direction
	is_dodging = false
	_dodge_animation_started = false
	_dodge_elapsed = 0.0
	_dodge_timeout = 0.0
	_dodge_direction = DodgeDirection.BACKWARD
	if interrupted:
		character.abort_dodge_animation()
	character.stop_dodge_motion_and_visuals()
	dodge_finished.emit(direction, interrupted)


func start_dodge_invulnerability() -> void:
	if is_dodging and not is_dizzy and not is_defeated:
		is_invulnerable = true


func stop_dodge_invulnerability() -> void:
	is_invulnerable = false


func _update_dodge(delta: float) -> void:
	if not is_dodging:
		return
	_dodge_elapsed += delta
	if is_defeated or is_dizzy:
		cancel_dodge()
	elif character.is_dodge_animation_playing():
		_dodge_animation_started = true
	elif _dodge_animation_started:
		cancel_dodge(false)
	if is_dodging and (_dodge_elapsed > _dodge_timeout or (not _dodge_animation_started and _dodge_elapsed > 0.25)):
		cancel_dodge()
