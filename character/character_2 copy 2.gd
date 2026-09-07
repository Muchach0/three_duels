extends CharacterBody3D

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

@export var idle_animation := "Idle/mixamo_com"
@export var walk_animation := "Walking (2)/mixamo_com"
@export var attack_animation := "Attacking/mixamo_com"
@export var attack_action := "attack"
@export var attack_filter_bones: Array[String] = [
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Spine2",
	"mixamorig_Neck",
	"mixamorig_Head",
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
	"mixamorig_LeftShoulder",
	"mixamorig_LeftArm",
	"mixamorig_LeftForeArm",
	"mixamorig_LeftHand",
]

@export_group("Customization")
@export var available_model_definitions: Array[CharacterModelDefinition] = []
@export var available_tint_presets: Array[Color] = [
	Color(1.0, 1.0, 1.0, 1.0),
	Color(1.0, 0.45, 0.38, 1.0),
	Color(0.35, 0.65, 1.0, 1.0),
	Color(0.45, 1.0, 0.55, 1.0),
]
@export var available_prop_definitions: Array[CharacterPropDefinition] = []

const STATE_IDLE := "Idle"
const STATE_WALK := "Walk"
const TREE_NODE_LOCOMOTION := "Locomotion"
const TREE_NODE_ATTACK := "Attack"
const TREE_NODE_ATTACK_ONE_SHOT := "AttackOneShot"

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var camera: Camera3D = $Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _camera_yaw := 0.0
var _camera_pitch := deg_to_rad(22.0)
var _facing_yaw := 0.0
var _left_dragging := false
var _right_dragging := false
var _movement_input := Vector2.ZERO
var _is_running := false
var _state_machine: AnimationNodeStateMachinePlayback
var _current_state := ""
var _active_skeleton: Skeleton3D
var _current_model_index := -1
var _current_tint_index := 0
var _current_tint := Color.WHITE
var _active_prop_definitions: Dictionary = {}
var _active_prop_nodes: Dictionary = {}
var _bone_attachments: Dictionary = {}


func _ready() -> void:
	_active_skeleton = get_node_or_null("Skeleton3D") as Skeleton3D
	_connect_customization_ui()
	_facing_yaw = rotation.y - character_model_yaw_offset
	_camera_yaw = _facing_yaw
	rotation.y = _facing_yaw + character_model_yaw_offset
	camera_distance = clamp(camera_distance, camera_min_distance, camera_max_distance)
	_setup_animation_tree()
	if not available_tint_presets.is_empty():
		_current_tint = available_tint_presets[_current_tint_index]
		apply_tint(_current_tint)
	_update_camera(1.0, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		match mouse_button.button_index:
			MOUSE_BUTTON_LEFT:
				_left_dragging = mouse_button.pressed
				if mouse_button.pressed:
					attack()
			MOUSE_BUTTON_RIGHT:
				_right_dragging = mouse_button.pressed
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
	if not attack_action.is_empty() and InputMap.has_action(attack_action) and Input.is_action_just_pressed(attack_action):
		attack()
	_update_camera(delta)


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
	var idle := _resolve_animation(idle_animation, "")
	var walk := _resolve_animation(walk_animation, idle)
	var attack_animation_name := _resolve_animation(attack_animation, "")

	var locomotion := AnimationNodeStateMachine.new()
	locomotion.add_node(STATE_IDLE, _animation_node(idle))
	locomotion.add_node(STATE_WALK, _animation_node(walk))
	_add_transition(locomotion, STATE_IDLE, STATE_WALK, 0.15)
	_add_transition(locomotion, STATE_WALK, STATE_IDLE, 0.15)

	var attack_one_shot := AnimationNodeOneShot.new()
	attack_one_shot.fadein_time = 0.08
	attack_one_shot.fadeout_time = 0.12
	attack_one_shot.filter_enabled = true
	_apply_attack_filter(attack_one_shot)

	var root := AnimationNodeBlendTree.new()
	root.add_node(TREE_NODE_LOCOMOTION, locomotion)
	root.add_node(TREE_NODE_ATTACK, _animation_node(attack_animation_name))
	root.add_node(TREE_NODE_ATTACK_ONE_SHOT, attack_one_shot)
	root.connect_node(TREE_NODE_ATTACK_ONE_SHOT, 0, TREE_NODE_LOCOMOTION)
	root.connect_node(TREE_NODE_ATTACK_ONE_SHOT, 1, TREE_NODE_ATTACK)
	root.connect_node("output", 0, TREE_NODE_ATTACK_ONE_SHOT)

	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.tree_root = root
	animation_tree.active = true
	_state_machine = animation_tree.get("parameters/%s/playback" % TREE_NODE_LOCOMOTION)
	_current_state = ""
	_travel(STATE_IDLE)


func _animation_node(animation_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = StringName(animation_name)
	return node


func _add_transition(root: AnimationNodeStateMachine, from: String, to: String, blend_time: float) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = blend_time
	root.add_transition(from, to, transition)


func _resolve_animation(animation_name: String, fallback: String) -> String:
	if animation_player.has_animation(animation_name):
		return animation_name

	if not fallback.is_empty() and animation_player.has_animation(fallback):
		push_warning("Missing animation '%s'; using '%s' instead." % [animation_name, fallback])
		return fallback

	push_warning("Missing animation '%s'; animation state will use RESET." % animation_name)
	return "RESET"


func _update_animation_state() -> void:
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	if horizontal_velocity.length() <= 0.1:
		_travel(STATE_IDLE)
	else:
		_travel(STATE_WALK)


func attack() -> void:
	if animation_tree == null or not animation_tree.active:
		return

	animation_tree.set(
		"parameters/%s/request" % TREE_NODE_ATTACK_ONE_SHOT,
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


func _travel(state_name: String) -> void:
	if _current_state == state_name or _state_machine == null:
		return

	_state_machine.travel(state_name)
	_current_state = state_name


func _apply_attack_filter(attack_one_shot: AnimationNodeOneShot) -> void:
	var skeleton := get_active_skeleton()
	if skeleton == null:
		push_warning("Cannot configure attack filter: no active Skeleton3D.")
		return

	for bone_name in attack_filter_bones:
		if skeleton.find_bone(bone_name) == -1:
			continue

		attack_one_shot.set_filter_path(NodePath("%s:%s" % [skeleton.name, bone_name]), true)


func _connect_customization_ui() -> void:
	if not EventBus.ui_color_button.is_connected(_on_color_button_pressed):
		EventBus.ui_color_button.connect(_on_color_button_pressed)
	if not EventBus.ui_model_button.is_connected(_on_model_button_pressed):
		EventBus.ui_model_button.connect(_on_model_button_pressed)
	if not EventBus.ui_sword_button.is_connected(_on_sword_button_pressed):
		EventBus.ui_sword_button.connect(_on_sword_button_pressed)
	if not EventBus.ui_helmet_button.is_connected(_on_helmet_button_pressed):
		EventBus.ui_helmet_button.connect(_on_helmet_button_pressed)
	if not EventBus.ui_left_shoulder_button.is_connected(_on_left_shoulder_button_pressed):
		EventBus.ui_left_shoulder_button.connect(_on_left_shoulder_button_pressed)
	if not EventBus.ui_right_shoulder_button.is_connected(_on_right_shoulder_button_pressed):
		EventBus.ui_right_shoulder_button.connect(_on_right_shoulder_button_pressed)


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


func unequip_slot(slot: String) -> void:
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
	var definition := _find_first_prop_in_slot(slot)
	if definition == null:
		push_warning("No prop definition assigned for slot '%s'." % slot)
		return

	toggle_prop(definition)


func _find_first_prop_in_slot(slot: String) -> CharacterPropDefinition:
	for definition in available_prop_definitions:
		if definition != null and definition.slot == slot:
			return definition

	return null


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
