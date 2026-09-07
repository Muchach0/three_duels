extends Resource
class_name CharacterPropDefinition

@export_enum("head", "right_hand", "left_hand", "back", "left_shoulder", "right_shoulder")
var slot := "right_hand"

@export var display_name := ""
@export var prop_scene: PackedScene
@export var target_bone_name := "mixamorig_RightHand"
@export var local_position := Vector3.ZERO
@export var local_rotation_degrees := Vector3.ZERO
@export var local_scale := Vector3.ONE
@export var gameplay_tags: Array[String] = []