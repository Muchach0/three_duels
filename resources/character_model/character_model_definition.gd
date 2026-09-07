extends Resource
class_name CharacterModelDefinition

@export var display_name := ""
@export var model_scene: PackedScene
@export var visual_root_name := "Skeleton3D"
@export var skeleton_node_path := NodePath("Skeleton3D")
@export var model_yaw_offset := PI
@export var model_scale := Vector3.ONE

@export var collision_radius := 0.1640625
@export var collision_height := 1.8098145
@export var collision_position := Vector3(0.0, 0.9017334, 0.0)
@export var camera_target_height := 1.8

@export var tintable_mesh_paths: Array[NodePath] = []
