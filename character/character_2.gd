extends CharacterBody3D

enum CharacterMode {
    PLAYER,
    ENEMY,
}

@export var character_mode := CharacterMode.PLAYER

@export var walk_speed := 3.5
@export var run_speed := 6.5
@export var backpedal_speed_multiplier := 0.65
@export var strafe_speed_multiplier := 0.85
@export var jump_velocity := 5.0
@export var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
@export var ground_acceleration := 18.0
@export var air_acceleration := 6.0
@export var deceleration := 20.0

@export var mouse_sensitivity := 0.005
@export var camera_zoom_speed := 0.5
@export var camera_min_distance := 1.8
@export var camera_max_distance := 6.5
@export var camera_distance := 3.2
@export var camera_pitch_min := deg_to_rad(-55.0)
@export var camera_pitch_max := deg_to_rad(70.0)
@export var camera_follow_smoothing := 18.0
@export var camera_target_height := 1.8
@export var character_model_yaw_offset := PI
@export var heavy_attack_hold_time := 0.45

@export_group("Customization")
@export var available_model_definitions: Array[CharacterModelDefinition] = []
@export var available_tint_presets: Array[Color] = [
    Color(1.0, 1.0, 1.0, 1.0),
    Color(1.0, 0.45, 0.38, 1.0),
    Color(0.35, 0.65, 1.0, 1.0),
    Color(0.45, 1.0, 0.55, 1.0),
]
@export var available_prop_definitions: Array[CharacterPropDefinition] = []
@export var initial_player_prop_definitions: Array[CharacterPropDefinition] = []

@export_group("Enemy")
@export var enemy_ai_profile: EnemyAiProfile
@export var enemy_model_index := 0
@export var enemy_tint_index := 0
@export var enemy_prop_slots: Array[String] = []

const STATE_IDLE := "Idle"
const STATE_WALK := "Walk"
const STATE_RUN := "Run"
const STATE_JUMP := "Jump"
const STATE_STRAFE_LEFT := "StrafeLeft"
const STATE_STRAFE_RIGHT := "StrafeRight"
const STATE_WALK_BACK := "WalkBack"
const TREE_NODE_LOCOMOTION := "Locomotion"
const TREE_NODE_BLOCK_BLEND := "BlockBlend"
const TREE_NODE_DIZZY_BLEND := "DizzyBlend"
const TREE_NODE_ATTACK_ONE_SHOT := "AttackOneShot"
const TREE_NODE_ATTACK_SELECTOR := "AttackSelector"
const TREE_NODE_BLOCK_IMPACT_ONE_SHOT := "BlockImpactOneShot"
const TREE_NODE_HIT_REACT_ONE_SHOT := "HitReactOneShot"
const TREE_NODE_DEATH_ONE_SHOT := "DeathOneShot"
const RIGHT_HAND_SLOT := "right_hand"
const ATTACK_SELECTOR_LIGHT := "Light"
const ATTACK_SELECTOR_HEAVY := "Heavy"
const ATTACK_METHOD_FILTER_PATHS: Array[NodePath] = [
    ^".",
    ^"",
]
const REQUIRED_ANIMATION_BONES: Array[String] = [
    "mixamorig_Hips",
    "mixamorig_Spine",
    "mixamorig_Spine1",
    "mixamorig_Spine2",
    "mixamorig_Neck",
    "mixamorig_Head",
    "mixamorig_LeftShoulder",
    "mixamorig_LeftArm",
    "mixamorig_LeftForeArm",
    "mixamorig_LeftHand",
    "mixamorig_LeftHandThumb1",
    "mixamorig_LeftHandThumb2",
    "mixamorig_LeftHandThumb3",
    "mixamorig_LeftHandIndex1",
    "mixamorig_LeftHandIndex2",
    "mixamorig_LeftHandIndex3",
    "mixamorig_LeftHandMiddle1",
    "mixamorig_LeftHandMiddle2",
    "mixamorig_LeftHandMiddle3",
    "mixamorig_LeftHandRing1",
    "mixamorig_LeftHandRing2",
    "mixamorig_LeftHandRing3",
    "mixamorig_LeftHandPinky1",
    "mixamorig_LeftHandPinky2",
    "mixamorig_LeftHandPinky3",
    "mixamorig_RightShoulder",
    "mixamorig_RightArm",
    "mixamorig_RightForeArm",
    "mixamorig_RightHand",
    "mixamorig_RightHandThumb1",
    "mixamorig_RightHandThumb2",
    "mixamorig_RightHandThumb3",
    "mixamorig_RightHandIndex1",
    "mixamorig_RightHandIndex2",
    "mixamorig_RightHandIndex3",
    "mixamorig_RightHandMiddle1",
    "mixamorig_RightHandMiddle2",
    "mixamorig_RightHandMiddle3",
    "mixamorig_RightHandRing1",
    "mixamorig_RightHandRing2",
    "mixamorig_RightHandRing3",
    "mixamorig_RightHandPinky1",
    "mixamorig_RightHandPinky2",
    "mixamorig_RightHandPinky3",
    "mixamorig_LeftUpLeg",
    "mixamorig_LeftLeg",
    "mixamorig_LeftFoot",
    "mixamorig_LeftToeBase",
    "mixamorig_RightUpLeg",
    "mixamorig_RightLeg",
    "mixamorig_RightFoot",
    "mixamorig_RightToeBase",
]

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera3D = $Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var hurtbox: Area3D = $Hurtbox
@onready var hurtbox_shape: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var combat_component: Combat_Component = $CombatComponent
@onready var ai_component: AiComponent = $AiComponent

var _camera_yaw := 0.0
var _camera_pitch := deg_to_rad(22.0)
var _facing_yaw := 0.0
var _left_dragging := false
var _right_dragging := false
var _left_attack_held := false
var _left_attack_hold_elapsed := 0.0
var _heavy_attack_fired := false
var _movement_input := Vector2.ZERO
var _is_running := false
var _state_machine: AnimationNodeStateMachinePlayback
var _attack_one_shot: AnimationNodeOneShot
var _block_impact_one_shot: AnimationNodeOneShot
var _hit_react_one_shot: AnimationNodeOneShot
var _death_one_shot: AnimationNodeOneShot
var _current_state := ""
var _active_skeleton: Skeleton3D
var _current_model_index := -1
var _current_tint_index := 0
var _current_tint := Color.WHITE
var _active_prop_definitions: Dictionary = {}
var _active_prop_nodes: Dictionary = {}
var _bone_attachments: Dictionary = {}
var _ai_movement_direction := Vector3.ZERO
var _ai_running := false


func _ready() -> void:
    _active_skeleton = get_node_or_null("Skeleton3D") as Skeleton3D
    _facing_yaw = rotation.y - character_model_yaw_offset
    _camera_yaw = _facing_yaw
    rotation.y = _facing_yaw + character_model_yaw_offset
    camera_distance = clamp(camera_distance, camera_min_distance, camera_max_distance)
    _setup_animation_tree()
    if not available_tint_presets.is_empty():
        _current_tint = available_tint_presets[_current_tint_index]
        apply_tint(_current_tint)

    combat_component.setup(self, hurtbox)

    if _is_player():
        _connect_customization_ui()
        _set_camera_current(true)
        _update_camera(1.0, true)
        _equip_initial_player_loadout()
    elif _is_enemy():
        _set_camera_current(false)
        _setup_enemy_from_exports()
        ai_component.setup(self, combat_component, enemy_ai_profile)

    EventBus.ui_test_sword_enable_collision.connect(_test_sword_collision)

func _unhandled_input(event: InputEvent) -> void:
    if not _is_player():
        return
    if is_dizzy():
        return

    if event is InputEventMouseButton:
        var mouse_button := event as InputEventMouseButton
        match mouse_button.button_index:
            MOUSE_BUTTON_LEFT:
                _left_dragging = mouse_button.pressed
                if mouse_button.pressed:
                    _start_left_attack_hold()
                else:
                    _release_left_attack_hold()
            MOUSE_BUTTON_RIGHT:
                _right_dragging = mouse_button.pressed
                if mouse_button.pressed:
                    _cancel_left_attack_hold()
                _set_blocking(mouse_button.pressed)
            MOUSE_BUTTON_WHEEL_UP:
                if mouse_button.pressed:
                    camera_distance = max(camera_min_distance, camera_distance - camera_zoom_speed)
            MOUSE_BUTTON_WHEEL_DOWN:
                if mouse_button.pressed:
                    camera_distance = min(camera_max_distance, camera_distance + camera_zoom_speed)
    elif event is InputEventMouseMotion and (_left_dragging or _right_dragging):
        var mouse_motion := event as InputEventMouseMotion
        _camera_yaw -= mouse_motion.relative.x * mouse_sensitivity
        _camera_pitch = clamp(
            _camera_pitch - mouse_motion.relative.y * mouse_sensitivity,
            camera_pitch_min,
            camera_pitch_max
        )

        if _right_dragging:
            _facing_yaw = _camera_yaw
            rotation.y = _facing_yaw + character_model_yaw_offset


func _physics_process(delta: float) -> void:
    if is_dizzy():
        _physics_process_incapacitated(delta)
    elif _is_player():
        _physics_process_player(delta)
    else:
        combat_component.physics_process(delta)
        ai_component.physics_process(delta)
        _physics_process_enemy(delta)
        return

    combat_component.physics_process(delta)


func _physics_process_incapacitated(delta: float) -> void:
    _movement_input = Vector2.ZERO
    _is_running = false
    velocity.x = 0.0
    velocity.z = 0.0

    if is_on_floor():
        if velocity.y < 0.0:
            velocity.y = 0.0
    else:
        velocity.y -= gravity * delta

    move_and_slide()
    _travel(STATE_IDLE)
    if _is_player():
        _update_camera(delta)


func _physics_process_player(delta: float) -> void:
    _update_left_attack_hold(delta)
    _movement_input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
    _is_running = _movement_input != Vector2.ZERO and Input.is_action_pressed("run")

    var target_horizontal_velocity := _get_target_horizontal_velocity()
    var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
    var acceleration := ground_acceleration if is_on_floor() else air_acceleration

    if target_horizontal_velocity.is_zero_approx():
        acceleration = deceleration

    horizontal_velocity = horizontal_velocity.move_toward(target_horizontal_velocity, acceleration * delta)
    velocity.x = horizontal_velocity.x
    velocity.z = horizontal_velocity.z

    if is_on_floor():
        if Input.is_action_just_pressed("jump"):
            velocity.y = jump_velocity
        elif velocity.y < 0.0:
            velocity.y = 0.0
    else:
        velocity.y -= gravity * delta

    move_and_slide()
    _update_animation_state()
    _update_camera(delta)


func _physics_process_enemy(delta: float) -> void:
    if is_defeated():
        clear_ai_movement()

    _is_running = _ai_running and not _ai_movement_direction.is_zero_approx()
    _movement_input = Vector2.ZERO
    if not _ai_movement_direction.is_zero_approx():
        var local_direction := global_transform.basis.inverse() * _ai_movement_direction
        _movement_input = Vector2(local_direction.x, -local_direction.z).normalized()

    var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
    var speed := run_speed if _is_running else walk_speed
    var target_horizontal_velocity := _ai_movement_direction * speed
    var acceleration := ground_acceleration if is_on_floor() else air_acceleration
    if target_horizontal_velocity.is_zero_approx():
        acceleration = deceleration
    horizontal_velocity = horizontal_velocity.move_toward(target_horizontal_velocity, acceleration * delta)
    velocity.x = horizontal_velocity.x
    velocity.z = horizontal_velocity.z

    if is_on_floor():
        if velocity.y < 0.0:
            velocity.y = 0.0
    else:
        velocity.y -= gravity * delta

    move_and_slide()
    _update_animation_state()


func set_ai_movement(world_direction: Vector3, running: bool) -> void:
    if not _is_enemy():
        return
    world_direction.y = 0.0
    _ai_movement_direction = world_direction.normalized()
    _ai_running = running


func clear_ai_movement() -> void:
    _ai_movement_direction = Vector3.ZERO
    _ai_running = false


func face_ai_target(world_position: Vector3) -> void:
    if not _is_enemy():
        return
    var direction := world_position - global_position
    direction.y = 0.0
    if direction.is_zero_approx():
        return
    _facing_yaw = atan2(-direction.x, -direction.z)
    rotation.y = _facing_yaw + character_model_yaw_offset


func _get_target_horizontal_velocity() -> Vector3:
    if _movement_input.is_zero_approx():
        return Vector3.ZERO

    var basis := Basis(Vector3.UP, _camera_yaw)
    var forward := -basis.z
    var right := basis.x
    var direction := (right * _movement_input.x + forward * _movement_input.y).normalized()

    var speed := run_speed if _is_running else walk_speed
    if _movement_input.y < 0.0:
        speed *= backpedal_speed_multiplier
    if not is_zero_approx(_movement_input.x) and is_zero_approx(_movement_input.y):
        speed *= strafe_speed_multiplier

    return direction * speed


func _update_camera(delta: float, snap := false) -> void:
    var target := global_position + Vector3.UP * camera_target_height
    var orbit := Basis(Vector3.UP, _camera_yaw) * Basis(Vector3.RIGHT, _camera_pitch)
    var desired_position := target + orbit * Vector3(0.0, 0.0, camera_distance)

    if snap:
        camera.global_position = desired_position
    else:
        var weight := 1.0 - exp(-camera_follow_smoothing * delta)
        camera.global_position = camera.global_position.lerp(desired_position, weight)

    camera.look_at(target, Vector3.UP)


func _setup_animation_tree() -> void:
    if animation_tree.tree_root == null:
        push_warning("AnimationTree has no tree_root configured.")
        return

    if not _active_skeleton_is_animation_compatible():
        animation_tree.active = false
        _state_machine = null
        _attack_one_shot = null
        _block_impact_one_shot = null
        _hit_react_one_shot = null
        _death_one_shot = null
        return

    animation_tree.active = true
    _state_machine = animation_tree.get("parameters/%s/playback" % TREE_NODE_LOCOMOTION)
    _attack_one_shot = _get_one_shot_node(TREE_NODE_ATTACK_ONE_SHOT)
    _block_impact_one_shot = _get_one_shot_node(TREE_NODE_BLOCK_IMPACT_ONE_SHOT)
    _hit_react_one_shot = _get_one_shot_node(TREE_NODE_HIT_REACT_ONE_SHOT)
    _death_one_shot = _get_one_shot_node(TREE_NODE_DEATH_ONE_SHOT)
    _ensure_attack_method_tracks_are_filtered_in()
    _select_attack_animation(Combat_Component.AttackType.LIGHT)
    _current_state = ""
    _set_blocking(false)
    _travel(STATE_IDLE)


func _update_animation_state() -> void:
    if is_defeated():
        return

    var horizontal_velocity := Vector2(velocity.x, velocity.z)
    var is_walking := horizontal_velocity.length() > 0.1
    var next_state := STATE_IDLE

    if not is_on_floor():
        next_state = STATE_JUMP
    elif not is_walking:
        next_state = STATE_IDLE
    elif _movement_input.y < -absf(_movement_input.x):
        next_state = STATE_WALK_BACK
    elif _movement_input.x > absf(_movement_input.y):
        next_state = STATE_STRAFE_RIGHT
    elif -_movement_input.x > absf(_movement_input.y):
        next_state = STATE_STRAFE_LEFT
    elif _is_running:
        next_state = STATE_RUN
    else:
        next_state = STATE_WALK

    if _is_player() or _is_attack_playing():
        _set_attack_filter_enabled(next_state != STATE_IDLE)
    _travel(next_state)


func _start_left_attack_hold() -> void:
    if _right_dragging:
        return

    _left_attack_held = true
    _left_attack_hold_elapsed = 0.0
    _heavy_attack_fired = false


func _release_left_attack_hold() -> void:
    if not _left_attack_held:
        return

    var should_fire_light := not _heavy_attack_fired
    _cancel_left_attack_hold()

    if should_fire_light:
        attack(Combat_Component.AttackType.LIGHT)


func _update_left_attack_hold(delta: float) -> void:
    if not _left_attack_held or _heavy_attack_fired:
        return
    if _right_dragging or is_dizzy():
        _cancel_left_attack_hold()
        return

    _left_attack_hold_elapsed += delta
    if _left_attack_hold_elapsed >= heavy_attack_hold_time:
        _heavy_attack_fired = true
        attack(Combat_Component.AttackType.HEAVY)


func _cancel_left_attack_hold() -> void:
    _left_attack_held = false
    _left_attack_hold_elapsed = 0.0
    _heavy_attack_fired = false


func attack(attack_type := Combat_Component.AttackType.LIGHT) -> bool:
    return combat_component.attack(attack_type)


func _set_blocking(blocking: bool) -> void:
    if blocking:
        _cancel_left_attack_hold()
    combat_component.set_blocking(blocking)


func receive_hit(attacker: Node, hit_data: Dictionary) -> void:
    combat_component.receive_hit(attacker, hit_data)


func is_player_character() -> bool:
    return _is_player()


func is_enemy_character() -> bool:
    return _is_enemy()


func is_defeated() -> bool:
    return combat_component != null and combat_component.is_defeated


func is_dizzy() -> bool:
    return combat_component != null and combat_component.is_dizzy


func reset_for_duel() -> void:
    if combat_component != null:
        combat_component.reset_for_duel()


func get_equipped_prop_definitions() -> Array[CharacterPropDefinition]:
    var definitions: Array[CharacterPropDefinition] = []
    for slot in ["right_hand", "left_hand", "head"]:
        var definition := _active_prop_definitions.get(slot) as CharacterPropDefinition
        if definition != null:
            definitions.append(definition)

    return definitions


func _is_attack_playing() -> bool:
    return bool(animation_tree.get("parameters/%s/active" % TREE_NODE_ATTACK_ONE_SHOT))


func _is_death_playing() -> bool:
    return bool(animation_tree.get("parameters/%s/active" % TREE_NODE_DEATH_ONE_SHOT))


func _get_one_shot_node(node_name: String) -> AnimationNodeOneShot:
    var blend_tree := animation_tree.tree_root as AnimationNodeBlendTree
    if blend_tree == null:
        push_warning("AnimationTree root must be an AnimationNodeBlendTree.")
        return null

    if not blend_tree.has_node(node_name):
        push_warning("AnimationTree is missing a %s node." % node_name)
        return null

    var one_shot := blend_tree.get_node(node_name) as AnimationNodeOneShot
    if one_shot == null:
        push_warning("AnimationTree is missing a %s node." % node_name)

    return one_shot


func _set_attack_filter_enabled(enabled: bool) -> void:
    if _attack_one_shot == null:
        return

    if _attack_one_shot.filter_enabled == enabled:
        return

    _attack_one_shot.filter_enabled = enabled


func _ensure_attack_method_tracks_are_filtered_in() -> void:
    if _attack_one_shot == null:
        return

    for path in ATTACK_METHOD_FILTER_PATHS:
        _attack_one_shot.set_filter_path(path, true)

    if animation_player == null:
        return

    for animation_name in animation_player.get_animation_list():
        var animation := animation_player.get_animation(animation_name)
        if animation == null:
            continue

        for track_index in animation.get_track_count():
            if animation.track_get_type(track_index) == Animation.TYPE_METHOD:
                _attack_one_shot.set_filter_path(animation.track_get_path(track_index), true)


func _is_player() -> bool:
    return character_mode == CharacterMode.PLAYER


func _is_enemy() -> bool:
    return character_mode == CharacterMode.ENEMY


func _test_sword_collision():
    combat_component.set_weapon_hitbox_active(true)


func can_play_attack_animation() -> bool:
    return animation_tree != null and animation_tree.active and not _is_attack_playing() and not is_dizzy()


func is_attack_animation_playing() -> bool:
    return _is_attack_playing()


func set_attack_filter_for_movement() -> void:
    var horizontal_velocity := Vector2(velocity.x, velocity.z)
    _set_attack_filter_enabled(horizontal_velocity.length() > 0.1)


func request_attack_animation(attack_type := Combat_Component.AttackType.LIGHT) -> void:
    if animation_tree == null or not animation_tree.active:
        return

    _select_attack_animation(attack_type)
    animation_tree.set(
        "parameters/%s/request" % TREE_NODE_ATTACK_ONE_SHOT,
        AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
    )


func _select_attack_animation(attack_type: int) -> void:
    var transition_request := ATTACK_SELECTOR_LIGHT
    if attack_type == Combat_Component.AttackType.HEAVY:
        transition_request = ATTACK_SELECTOR_HEAVY

    animation_tree.set(
        "parameters/%s/transition_request" % TREE_NODE_ATTACK_SELECTOR,
        transition_request
    )


func abort_attack_animation() -> void:
    if animation_tree == null or not animation_tree.active:
        return

    animation_tree.set(
        "parameters/%s/request" % TREE_NODE_ATTACK_ONE_SHOT,
        AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT
    )


func reset_combat_animation() -> void:
    if animation_tree == null or not animation_tree.active:
        return

    for node_name in [TREE_NODE_ATTACK_ONE_SHOT, TREE_NODE_HIT_REACT_ONE_SHOT, TREE_NODE_BLOCK_IMPACT_ONE_SHOT, TREE_NODE_DEATH_ONE_SHOT]:
        animation_tree.set(
            "parameters/%s/request" % node_name,
            AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT
        )
    _travel(STATE_IDLE)


func set_block_animation(blocking: bool) -> void:
    if animation_tree == null or not animation_tree.active:
        return

    animation_tree.set(
        "parameters/%s/blend_amount" % TREE_NODE_BLOCK_BLEND,
        1.0 if blocking else 0.0
    )


func set_dizzy_animation(dizzy: bool) -> void:
    if animation_tree == null or not animation_tree.active:
        return

    animation_tree.set(
        "parameters/%s/blend_amount" % TREE_NODE_DIZZY_BLEND,
        1.0 if dizzy else 0.0
    )


func clear_combat_inputs() -> void:
    _left_dragging = false
    _right_dragging = false
    _cancel_left_attack_hold()
    _movement_input = Vector2.ZERO
    _is_running = false


func play_hit_react() -> void:
    if animation_tree == null or not animation_tree.active or _hit_react_one_shot == null or is_defeated():
        return

    animation_tree.set(
        "parameters/%s/request" % TREE_NODE_HIT_REACT_ONE_SHOT,
        AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
    )


func play_block_impact() -> void:
    if animation_tree == null or not animation_tree.active or _block_impact_one_shot == null or is_defeated():
        return

    animation_tree.set(
        "parameters/%s/request" % TREE_NODE_BLOCK_IMPACT_ONE_SHOT,
        AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
    )


func play_death() -> void:
    if animation_tree == null or not animation_tree.active or _death_one_shot == null or _is_death_playing():
        return

    animation_tree.set(
        "parameters/%s/request" % TREE_NODE_DEATH_ONE_SHOT,
        AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
    )


func _set_camera_current(is_current: bool) -> void:
    if camera == null:
        return

    camera.current = is_current


func _travel(state_name: String) -> void:
    if _current_state == state_name or _state_machine == null:
        return

    _state_machine.travel(state_name)
    _current_state = state_name


func _connect_customization_ui() -> void:
    if not _is_player():
        return

    if not EventBus.ui_color_button.is_connected(_on_color_button_pressed):
        EventBus.ui_color_button.connect(_on_color_button_pressed)
    if not EventBus.ui_model_button.is_connected(_on_model_button_pressed):
        EventBus.ui_model_button.connect(_on_model_button_pressed)
    if not EventBus.ui_sword_button.is_connected(_on_sword_button_pressed):
        EventBus.ui_sword_button.connect(_on_sword_button_pressed)
    if not EventBus.ui_left_hand_button.is_connected(_on_left_hand_button_pressed):
        EventBus.ui_left_hand_button.connect(_on_left_hand_button_pressed)
    if not EventBus.ui_helmet_button.is_connected(_on_helmet_button_pressed):
        EventBus.ui_helmet_button.connect(_on_helmet_button_pressed)
    if not EventBus.ui_left_shoulder_button.is_connected(_on_left_shoulder_button_pressed):
        EventBus.ui_left_shoulder_button.connect(_on_left_shoulder_button_pressed)
    if not EventBus.ui_right_shoulder_button.is_connected(_on_right_shoulder_button_pressed):
        EventBus.ui_right_shoulder_button.connect(_on_right_shoulder_button_pressed)


func _equip_initial_player_loadout() -> void:
    for definition in initial_player_prop_definitions:
        if definition == null:
            push_warning("Cannot equip initial player prop: definition is empty on %s." % name)
            continue

        equip_prop(definition)


func _setup_enemy_from_exports() -> void:
    if not available_model_definitions.is_empty():
        var model_index := clampi(enemy_model_index, 0, available_model_definitions.size() - 1)
        if model_index != enemy_model_index:
            push_warning("Enemy model index %d is out of range on %s; using %d." % [enemy_model_index, name, model_index])
        _current_model_index = model_index
        set_model(available_model_definitions[model_index])

    if not available_tint_presets.is_empty():
        var tint_index := clampi(enemy_tint_index, 0, available_tint_presets.size() - 1)
        if tint_index != enemy_tint_index:
            push_warning("Enemy tint index %d is out of range on %s; using %d." % [enemy_tint_index, name, tint_index])
        _current_tint_index = tint_index
        apply_tint(available_tint_presets[tint_index])

    for slot in enemy_prop_slots:
        var definitions := _find_props_in_slot(slot)
        if definitions.is_empty():
            push_warning("No enemy prop definition assigned for slot '%s' on %s." % [slot, name])
            continue

        equip_prop(definitions[0])

    _movement_input = Vector2.ZERO
    _is_running = false
    velocity.x = 0.0
    velocity.z = 0.0
    if animation_tree != null and animation_tree.active:
        _travel(STATE_IDLE)


func _on_color_button_pressed() -> void:
    if available_tint_presets.is_empty():
        push_warning("No tint presets assigned on %s." % name)
        return

    _current_tint_index = (_current_tint_index + 1) % available_tint_presets.size()
    apply_tint(available_tint_presets[_current_tint_index])


func _on_model_button_pressed() -> void:
    if available_model_definitions.is_empty():
        push_warning("No model definitions assigned on %s." % name)
        return

    _current_model_index = (_current_model_index + 1) % available_model_definitions.size()
    set_model(available_model_definitions[_current_model_index])


func _on_sword_button_pressed() -> void:
    _toggle_first_prop_in_slot("right_hand")

func _on_left_hand_button_pressed() -> void:
    _toggle_first_prop_in_slot("left_hand")

func _on_helmet_button_pressed() -> void:
    _toggle_first_prop_in_slot("head")


func _on_left_shoulder_button_pressed() -> void:
    _toggle_first_prop_in_slot("left_shoulder")


func _on_right_shoulder_button_pressed() -> void:
    _toggle_first_prop_in_slot("right_shoulder")


func set_model(definition: CharacterModelDefinition) -> void:
    if definition == null:
        push_warning("Cannot set character model: definition is empty.")
        return
    if definition.model_scene == null:
        push_warning("Cannot set character model '%s': model_scene is empty." % definition.display_name)
        return

    var model_instance := definition.model_scene.instantiate()
    var next_skeleton := _find_definition_skeleton(model_instance, definition)
    if next_skeleton == null:
        push_warning("Cannot set character model '%s': no Skeleton3D was found." % definition.display_name)
        model_instance.queue_free()
        return
    if not _skeleton_has_animation_bones(next_skeleton):
        push_warning("Cannot set character model '%s': skeleton is not Mixamo-compatible for the shared AnimationTree." % definition.display_name)
        model_instance.queue_free()
        return

    animation_tree.active = false
    combat_component.clear_weapon_hitbox()
    if _active_skeleton != null and is_instance_valid(_active_skeleton):
        var active_parent := _active_skeleton.get_parent()
        if active_parent != null:
            active_parent.remove_child(_active_skeleton)
        _active_skeleton.queue_free()

    var original_parent := next_skeleton.get_parent()
    if original_parent != null:
        original_parent.remove_child(next_skeleton)

    _clear_owner_recursive(next_skeleton)
    add_child(next_skeleton)
    move_child(next_skeleton, 0)
    next_skeleton.name = "Skeleton3D"
    next_skeleton.transform = Transform3D.IDENTITY
    next_skeleton.scale = definition.model_scale
    _active_skeleton = next_skeleton
    if model_instance != next_skeleton:
        model_instance.queue_free()

    character_model_yaw_offset = definition.model_yaw_offset
    rotation.y = _facing_yaw + character_model_yaw_offset
    camera_target_height = definition.camera_target_height
    _apply_collision_definition(definition)
    _setup_animation_tree()
    apply_tint(_current_tint)
    _recreate_equipped_props()


func _active_skeleton_is_animation_compatible() -> bool:
    var skeleton := get_active_skeleton()
    if skeleton == null:
        push_warning("AnimationTree cannot run: no active Skeleton3D.")
        return false

    return _skeleton_has_animation_bones(skeleton)


func _skeleton_has_animation_bones(skeleton: Skeleton3D) -> bool:
    var missing_bones: Array[String] = []
    for bone_name in REQUIRED_ANIMATION_BONES:
        if skeleton.find_bone(bone_name) == -1:
            missing_bones.append(bone_name)

    if not missing_bones.is_empty():
        push_warning("Skeleton '%s' is missing AnimationTree bones: %s" % [skeleton.name, ", ".join(missing_bones)])
        return false

    return true


func apply_tint(color: Color) -> void:
    _current_tint = color
    var meshes := _get_tintable_meshes()
    for mesh_instance in meshes:
        _apply_tint_to_mesh(mesh_instance, color)


func equip_prop(definition: CharacterPropDefinition) -> void:
    if definition == null:
        push_warning("Cannot equip prop: definition is empty.")
        return
    if definition.prop_scene == null:
        push_warning("Cannot equip prop '%s': prop_scene is empty." % definition.display_name)
        return

    var skeleton := get_active_skeleton()
    if skeleton == null:
        push_warning("Cannot equip prop '%s': no active Skeleton3D." % definition.display_name)
        return
    if skeleton.find_bone(definition.target_bone_name) == -1:
        push_warning("Cannot equip prop '%s': bone '%s' was not found." % [definition.display_name, definition.target_bone_name])
        return

    unequip_slot(definition.slot)
    var attachment := _get_or_create_bone_attachment(definition.slot, definition.target_bone_name)
    var prop_instance := definition.prop_scene.instantiate() as Node3D
    if prop_instance == null:
        push_warning("Cannot equip prop '%s': prop scene root must be Node3D." % definition.display_name)
        return

    attachment.add_child(prop_instance)
    prop_instance.position = definition.local_position
    prop_instance.rotation_degrees = definition.local_rotation_degrees
    prop_instance.scale = definition.local_scale
    _active_prop_definitions[definition.slot] = definition
    _active_prop_nodes[definition.slot] = prop_instance
    if definition.slot == RIGHT_HAND_SLOT:
        combat_component.set_weapon_hitbox(combat_component.find_weapon_hitbox(prop_instance))


func unequip_slot(slot: String) -> void:
    if slot == RIGHT_HAND_SLOT:
        combat_component.clear_weapon_hitbox()

    var prop_node := _active_prop_nodes.get(slot) as Node
    if prop_node != null and is_instance_valid(prop_node):
        prop_node.queue_free()

    _active_prop_nodes.erase(slot)
    _active_prop_definitions.erase(slot)


func toggle_prop(definition: CharacterPropDefinition) -> void:
    if definition == null:
        push_warning("Cannot toggle prop: definition is empty.")
        return

    if _active_prop_definitions.get(definition.slot) == definition:
        unequip_slot(definition.slot)
    else:
        equip_prop(definition)


func get_active_skeleton() -> Skeleton3D:
    if _active_skeleton != null and is_instance_valid(_active_skeleton):
        return _active_skeleton

    _active_skeleton = get_node_or_null("Skeleton3D") as Skeleton3D
    return _active_skeleton


func _find_definition_skeleton(model_instance: Node, definition: CharacterModelDefinition) -> Skeleton3D:
    if not definition.skeleton_node_path.is_empty() and model_instance.has_node(definition.skeleton_node_path):
        var skeleton := model_instance.get_node(definition.skeleton_node_path) as Skeleton3D
        if skeleton != null:
            return skeleton

    return _find_first_skeleton(model_instance)


func _find_first_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D

    for child in node.get_children():
        var skeleton := _find_first_skeleton(child)
        if skeleton != null:
            return skeleton

    return null


func _clear_owner_recursive(node: Node) -> void:
    node.owner = null
    for child in node.get_children():
        _clear_owner_recursive(child)


func _apply_collision_definition(definition: CharacterModelDefinition) -> void:
    if collision_shape == null:
        return

    var capsule := collision_shape.shape as CapsuleShape3D
    if capsule == null:
        push_warning("Character collision shape is not a CapsuleShape3D; model collision values were not applied.")
        return

    capsule.radius = definition.collision_radius
    capsule.height = definition.collision_height
    collision_shape.position = _get_collision_position(definition)

    var combat_capsule := hurtbox_shape.shape as CapsuleShape3D
    if combat_capsule != null:
        combat_capsule.radius = definition.collision_radius * 1.08
        combat_capsule.height = definition.collision_height * 1.02
        hurtbox_shape.position = _get_collision_position(definition)


func _get_collision_position(definition: CharacterModelDefinition) -> Vector3:
    if definition.collision_position.is_zero_approx():
        return Vector3(0.0, definition.collision_height * 0.5, 0.0)

    return definition.collision_position


func _get_tintable_meshes() -> Array[MeshInstance3D]:
    var meshes: Array[MeshInstance3D] = []
    var skeleton := get_active_skeleton()
    if skeleton == null:
        return meshes

    _collect_meshes(skeleton, meshes)
    return meshes


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        meshes.append(node as MeshInstance3D)

    for child in node.get_children():
        if child is BoneAttachment3D:
            continue
        _collect_meshes(child, meshes)


func _apply_tint_to_mesh(mesh_instance: MeshInstance3D, color: Color) -> void:
    if mesh_instance.mesh == null:
        return

    for surface_index in mesh_instance.mesh.get_surface_count():
        var material := mesh_instance.get_surface_override_material(surface_index)
        if material == null:
            material = mesh_instance.mesh.surface_get_material(surface_index)

        var tinted_material: BaseMaterial3D
        if material is BaseMaterial3D:
            tinted_material = (material as BaseMaterial3D).duplicate()
        else:
            tinted_material = StandardMaterial3D.new()

        tinted_material.albedo_color = color
        mesh_instance.set_surface_override_material(surface_index, tinted_material)


func _toggle_first_prop_in_slot(slot: String) -> void:
    var definitions := _find_props_in_slot(slot)
    if definitions.is_empty():
        push_warning("No prop definition assigned for slot '%s'." % slot)
        return

    var next_definition_index := 0
    var active_definition := _active_prop_definitions.get(slot) as CharacterPropDefinition
    if active_definition != null:
        var active_definition_index := definitions.find(active_definition)
        if active_definition_index != -1:
            next_definition_index = (active_definition_index + 1) % definitions.size()

    equip_prop(definitions[next_definition_index])


func _find_props_in_slot(slot: String) -> Array[CharacterPropDefinition]:
    var definitions: Array[CharacterPropDefinition] = []
    for definition in available_prop_definitions:
        if definition != null and definition.slot == slot:
            definitions.append(definition)

    return definitions


func _get_or_create_bone_attachment(slot: String, bone_name: String) -> BoneAttachment3D:
    var attachment := _bone_attachments.get(slot) as BoneAttachment3D
    if attachment != null and is_instance_valid(attachment):
        attachment.bone_name = bone_name
        return attachment

    attachment = BoneAttachment3D.new()
    attachment.name = "%sAttachment" % slot.to_pascal_case()
    attachment.bone_name = bone_name
    get_active_skeleton().add_child(attachment)
    _bone_attachments[slot] = attachment
    return attachment


func _recreate_equipped_props() -> void:
    var equipped_definitions: Array[CharacterPropDefinition] = []
    for definition in _active_prop_definitions.values():
        if definition != null:
            equipped_definitions.append(definition)

    _active_prop_definitions.clear()
    _active_prop_nodes.clear()
    _bone_attachments.clear()

    for definition in equipped_definitions:
        equip_prop(definition)


func _combat_hitbox_open() -> void:
    combat_component.open_hitbox()

func _combat_hitbox_close() -> void:
    combat_component.close_hitbox()
