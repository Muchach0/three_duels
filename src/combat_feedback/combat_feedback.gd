extends Node3D

const POPUP := preload("res://src/combat_feedback/combat_popup.tscn")
const HIT_BURST := preload("res://src/combat_feedback/hit_burst.tscn")
const BLOCK_BURST := preload("res://src/combat_feedback/block_burst.tscn")
const POPUP_OFFSETS := [Vector2.ZERO, Vector2(-38, -14), Vector2(38, -28)]

@onready var popups: CanvasLayer = $Popups
@onready var bursts: Node3D = $Bursts


func _ready() -> void:
    EventBus.combat_hit_resolved.connect(_on_hit_resolved)


func clear() -> void:
    for container in [popups, bursts]:
        for effect in container.get_children():
            effect.free()


func _on_hit_resolved(defender: Node3D, result: Dictionary) -> void:
    if not is_inside_tree() or defender.get_viewport() != get_viewport():
        return
    # The shared character contract supplies a capsule, updated when its model changes.
    var shape: CollisionShape3D = defender.get_node("Hurtbox/CollisionShape3D")
    var capsule := shape.shape as CapsuleShape3D
    var shape_scale := shape.global_basis.get_scale()
    var center: Vector3 = result.position + (shape.global_position - defender.global_position)
    var height := capsule.height * shape_scale.y
    var toward_attacker: Vector3 = result.attacker_position - result.position
    toward_attacker.y = 0.0
    toward_attacker = toward_attacker.normalized()
    var impact := center + Vector3.UP * height * 0.2 + toward_attacker * capsule.radius * maxf(shape_scale.x, shape_scale.z)
    var anchor := center + Vector3.UP * (height * 0.5 + 0.2)

    var popup := POPUP.instantiate()
    # Derive staggering from live popups; no per-defender cache survives a despawn.
    var overlap_count := 0
    for existing in popups.get_children():
        if existing.world_position.distance_squared_to(anchor) < 1.0:
            overlap_count += 1
    popups.add_child(popup)
    popup.setup(result, defender.is_player_character(), anchor, POPUP_OFFSETS[overlap_count % POPUP_OFFSETS.size()])
    if result.blocked:
        _spawn_burst(BLOCK_BURST, impact)
    if result.health_lost > 0.0:
        _spawn_burst(HIT_BURST, impact)


func _spawn_burst(scene: PackedScene, world_position: Vector3) -> void:
    var burst := scene.instantiate() as CPUParticles3D
    # Set the transform before _ready starts emission, including in translated arenas.
    burst.position = bursts.to_local(world_position)
    bursts.add_child(burst)
