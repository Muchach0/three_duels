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

@export_group("Combat Characteristics")
## Extra health damage for both attacks when equipped in right_hand.
@export_range(0.0, 1000.0, 1.0, "or_greater") var damage_bonus := 0.0:
	set(value):
		damage_bonus = maxf(value, 0.0)
## Reduces stamina/guard spent per blocked hit when equipped in left_hand.
@export_range(0.0, 1000.0, 1.0, "or_greater") var block_value := 0.0:
	set(value):
		block_value = maxf(value, 0.0)
## Reduces remaining health damage after blocking when equipped in head.
@export_range(0.0, 1000.0, 1.0, "or_greater") var armor_value := 0.0:
	set(value):
		armor_value = maxf(value, 0.0)
