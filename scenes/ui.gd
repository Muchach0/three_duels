
extends Node

@onready var player_health_bar: ProgressBar = $CanvasLayer/PlayerControl/HBoxContainer/EnemyLifeBar
@onready var player_guard_bar: ProgressBar = $CanvasLayer/PlayerControl/HBoxContainer/EnemyGuardBar
@onready var enemy_list: VBoxContainer = $CanvasLayer/EnemyControl/HBoxContainer
@onready var enemy_label: Label = $CanvasLayer/EnemyControl/HBoxContainer/EnemyLabel
@onready var enemy_profile_label: Label = $CanvasLayer/EnemyControl/HBoxContainer/ProfileLabel
@onready var enemy_state_label: Label = $CanvasLayer/EnemyControl/HBoxContainer/StateLabel
@onready var enemy_health_bar: ProgressBar = $CanvasLayer/EnemyControl/HBoxContainer/EnemyLifeBar
@onready var enemy_guard_bar: ProgressBar = $CanvasLayer/EnemyControl/HBoxContainer/EnemyGuardBar

var _enemy_rows: Dictionary = {}


func _ready() -> void:
    if not EventBus.combat_stats_changed.is_connected(_on_combat_stats_changed):
        EventBus.combat_stats_changed.connect(_on_combat_stats_changed)
    _sync_existing_combat_characters.call_deferred()


func _on_right_shoulder_button_pressed() -> void:
    EventBus.ui_right_shoulder_button.emit()

func _on_left_shoulder_button_pressed() -> void:
    EventBus.ui_left_shoulder_button.emit()

func _on_helmet_button_pressed() -> void:
    EventBus.ui_helmet_button.emit()

func _on_sword_button_pressed() -> void:
    EventBus.ui_sword_button.emit()

func _on_model_button_pressed() -> void:
    EventBus.ui_model_button.emit()

func _on_color_button_pressed() -> void:
    EventBus.ui_color_button.emit()

func _on_left_hand_button_pressed() -> void:
    EventBus.ui_left_hand_button.emit()

func _on_exit_button_pressed() -> void:
    EventBus.ui_exit_button.emit()
    get_tree().quit()

func _on_sword_collision_button_pressed() -> void:
    EventBus.ui_test_sword_enable_collision.emit()



func _sync_existing_combat_characters() -> void:
    for character in get_tree().get_nodes_in_group("combat_character"):
        if character.has_method("is_player_character") or character.has_method("is_enemy_character"):
            var combat_component := character.get_node_or_null("CombatComponent") as Combat_Component
            if combat_component == null:
                continue

            _update_character_stats(
                character,
                combat_component.health,
                combat_component.max_health,
                combat_component.guard,
                combat_component.max_guard
            )
            if character.is_enemy_character():
                _connect_enemy_ai(character)


func _on_combat_stats_changed(character: Node, health: float, max_health: float, guard: float, max_guard: float) -> void:
    _update_character_stats(character, health, max_health, guard, max_guard)


func _update_character_stats(character: Node, health: float, max_health: float, guard: float, max_guard: float) -> void:
    if character.has_method("is_player_character") and character.is_player_character():
        _set_bars(player_health_bar, player_guard_bar, health, max_health, guard, max_guard)
    elif character.has_method("is_enemy_character") and character.is_enemy_character():
        var row := _get_enemy_row(character)
        var label := row["label"] as Label
        var health_bar := row["health_bar"] as ProgressBar
        var guard_bar := row["guard_bar"] as ProgressBar
        label.text = character.name
        _update_enemy_ai_labels(character, row)
        _set_bars(health_bar, guard_bar, health, max_health, guard, max_guard)


func _set_bars(health_bar: ProgressBar, guard_bar: ProgressBar, health_value: float, max_health_value: float, guard_value: float, max_guard_value: float) -> void:
    health_bar.max_value = maxf(max_health_value, 1.0)
    health_bar.value = clampf(health_value, 0.0, health_bar.max_value)
    guard_bar.max_value = maxf(max_guard_value, 1.0)
    guard_bar.value = clampf(guard_value, 0.0, guard_bar.max_value)


func _get_enemy_row(character: Node) -> Dictionary:
    var key := character.get_instance_id()
    if _enemy_rows.has(key):
        return _enemy_rows[key]

    var row: Dictionary
    if _enemy_rows.is_empty():
        row = {
            "label": enemy_label,
            "profile_label": enemy_profile_label,
            "state_label": enemy_state_label,
            "health_bar": enemy_health_bar,
            "guard_bar": enemy_guard_bar,
        }
    else:
        row = _create_enemy_row(character.name)

    _enemy_rows[key] = row
    return row


func _create_enemy_row(label_text: String) -> Dictionary:
    var label := Label.new()
    label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    label.text = label_text
    enemy_list.add_child(label)

    var profile_label := Label.new()
    profile_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    enemy_list.add_child(profile_label)

    var state_label := Label.new()
    state_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    enemy_list.add_child(state_label)

    var health_bar := ProgressBar.new()
    health_bar.step = 1.0
    enemy_list.add_child(health_bar)

    var guard_bar := ProgressBar.new()
    guard_bar.step = 1.0
    enemy_list.add_child(guard_bar)

    return {
        "label": label,
        "profile_label": profile_label,
        "state_label": state_label,
        "health_bar": health_bar,
        "guard_bar": guard_bar,
    }



func _on_enemy_attack_button_pressed() -> void:
    EventBus.ui_test_enemy_attack.emit()


func _on_enemy_block_button_pressed() -> void:
    EventBus.ui_test_enemy_block.emit()


func _on_enemy_idle_button_pressed() -> void:
    EventBus.ui_test_enemy_idle.emit()


func _on_clear_enemy_override_button_pressed() -> void:
    EventBus.ui_test_enemy_clear_override.emit()


func _connect_enemy_ai(character: Node) -> void:
    var ai_component := character.get_node_or_null("AiComponent") as AiComponent
    if ai_component != null and not ai_component.state_changed.is_connected(_on_enemy_ai_state_changed):
        ai_component.state_changed.connect(_on_enemy_ai_state_changed)
    _update_enemy_ai_labels(character, _get_enemy_row(character))


func _on_enemy_ai_state_changed(character: Node, _state_name: String) -> void:
    _update_enemy_ai_labels(character, _get_enemy_row(character))


func _update_enemy_ai_labels(character: Node, row: Dictionary) -> void:
    var profile_label := row["profile_label"] as Label
    var state_label := row["state_label"] as Label
    var ai_component := character.get_node_or_null("AiComponent") as AiComponent
    if ai_component == null:
        profile_label.text = "Profile: -"
        state_label.text = "State: -"
        return
    profile_label.text = "Profile: %s" % (ai_component.profile.profile_name if ai_component.profile != null else "Default")
    state_label.text = "State: %s" % ai_component.get_current_state_name()
