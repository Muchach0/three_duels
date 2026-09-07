extends Resource
class_name EnemyAiProfile

enum Tier {
	LOW,
	MEDIUM,
	HIGH,
}

@export var profile_name := "Enemy"
@export var attack_speed := Tier.LOW
@export var aggression := Tier.LOW
@export var block_chance := Tier.LOW
@export var openings := Tier.LOW

@export_group("Sensing")
@export var perception_radius := 12.0
@export var attack_range := 1.8
@export var target_loss_grace_period := 0.5
@export var reaction_range := 2.5

@export_group("Actions")
@export var block_duration := 0.65
@export var block_reaction_delay := 0.05
@export var light_attack_weight := 1.0
@export var heavy_attack_weight := 0.0
@export_range(0.0, 1.0, 0.01) var combo_probability := 0.0
@export_range(1, 3, 1) var max_combo_length := 1
@export var approach_running := false


func get_attack_decision_delay() -> float:
	return _get_tier_value(attack_speed, 1.20, 0.70, 0.30)


func get_aggression_probability() -> float:
	return _get_tier_value(aggression, 0.30, 0.60, 0.85)


func get_block_probability() -> float:
	return _get_tier_value(block_chance, 0.15, 0.45, 0.80)


func get_opening_duration() -> float:
	return _get_tier_value(openings, 0.30, 0.70, 1.20)


func can_use_heavy_attack() -> bool:
	return heavy_attack_weight > 0.0


func choose_attack_type(rng: RandomNumberGenerator) -> int:
	if not can_use_heavy_attack():
		return Combat_Component.AttackType.LIGHT

	var light_weight := maxf(light_attack_weight, 0.0)
	var total_weight := light_weight + heavy_attack_weight
	if total_weight <= 0.0:
		return Combat_Component.AttackType.LIGHT
	return Combat_Component.AttackType.HEAVY if rng.randf() >= light_weight / total_weight else Combat_Component.AttackType.LIGHT


func _get_tier_value(tier: Tier, low: float, medium: float, high: float) -> float:
	match tier:
		Tier.MEDIUM:
			return medium
		Tier.HIGH:
			return high
		_:
			return low
