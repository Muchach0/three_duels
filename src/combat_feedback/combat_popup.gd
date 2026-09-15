extends Control

const DURATION := 0.7
const DAMAGE_COLOR := Color(1.0, 0.22, 0.18)
const BLOCK_COLOR := Color(1.0, 0.86, 0.12)

var world_position := Vector3.ZERO
var screen_offset := Vector2.ZERO
var rise := 0.0

@onready var content: VBoxContainer = $Content
@onready var status_label: Label = $Content/Status
@onready var damage_label: Label = $Content/Damage


func setup(result: Dictionary, player_hit: bool, anchor: Vector3, offset: Vector2) -> void:
    world_position = anchor
    screen_offset = offset
    var damage: float = result.health_lost
    if result.defense_broken:
        status_label.text = "stamina broken" if player_hit else "guard broken"
    elif result.blocked:
        status_label.text = "blocked"
    elif damage <= 0.0:
        status_label.text = "absorbed"
    status_label.visible = not status_label.text.is_empty()
    status_label.add_theme_color_override("font_color", BLOCK_COLOR if result.blocked else Color.WHITE)
    damage_label.visible = damage > 0.0
    if damage > 0.0:
        # Retain fractional damage without displaying a misleading zero for tiny hits.
        damage_label.text = "<0.1" if damage < 0.05 else ("%.1f" % damage).trim_suffix(".0")
    damage_label.add_theme_color_override("font_color", DAMAGE_COLOR if player_hit else Color.WHITE)
    content.scale = Vector2.ONE * 0.65
    var tween := create_tween().set_parallel()
    tween.tween_property(content, "scale", Vector2.ONE * 1.18, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tween.tween_property(content, "scale", Vector2.ONE, 0.12).set_delay(0.08)
    tween.tween_property(self, "rise", 48.0, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(self, "modulate:a", 0.0, 0.28).set_delay(DURATION - 0.28)
    tween.finished.connect(queue_free)
    _process(0.0)


func _process(_delta: float) -> void:
    var camera := get_viewport().get_camera_3d()
    visible = camera != null and not camera.is_position_behind(world_position)
    if not visible:
        return
    position = camera.unproject_position(world_position) + screen_offset - Vector2(0, rise)
    content.pivot_offset = content.size * 0.5
    content.position = -content.pivot_offset
