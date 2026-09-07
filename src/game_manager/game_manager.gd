extends Node


enum State {
    MAIN_MENU,
    DUEL,
    UPGRADE_SELECTION,
    DEFEAT,
    VICTORY,
}


const ARENA_SCENE: PackedScene = preload("res://scenes/arena.tscn")
const PLAYER_SCENE: PackedScene = preload("res://character/character_2.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const UPGRADE_MENU_SCENE: PackedScene = preload("res://scenes/choice_upgrade_menu.tscn")
const DEFEAT_MENU_SCENE: PackedScene = preload("res://scenes/defeat_menu.tscn")
const VICTORY_MENU_SCENE: PackedScene = preload("res://scenes/victory_menu.tscn")
const FALLBACK_PLAYER_SPAWN := Vector3(-2.0, 0.0, 0.0)
const FALLBACK_ENEMY_SPAWN := Vector3(2.0, 0.0, 0.0)
const DUEL_CONFIG := [
    {
        "enemy_scene": preload("res://character/instantiated_character/soldier.tscn"),
        "enemy_name": "Soldier",
    },
    {
        "enemy_scene": preload("res://character/instantiated_character/guardian.tscn"),
        "enemy_name": "Guardian",
    },
    {
        "enemy_scene": preload("res://character/instantiated_character/champion.tscn"),
        "enemy_name": "Champion",
    },
]


@onready var world_root: Node3D = $WorldRoot
@onready var ui_root: CanvasLayer = $UIRoot

var flow_state := State.MAIN_MENU
var current_duel_index := 0
var selected_props_by_slot: Dictionary = {}
var player_instance: Node3D
var arena_instance: Node3D
var enemy_instance: Node3D
var current_menu: Control
var _current_reward_props: Array[CharacterPropDefinition] = []


func _ready() -> void:
    if not EventBus.combat_character_defeated.is_connected(_on_character_defeated):
        EventBus.combat_character_defeated.connect(_on_character_defeated)
    show_main_menu()


func show_main_menu() -> void:
    flow_state = State.MAIN_MENU
    selected_props_by_slot.clear()
    current_duel_index = 0
    _current_reward_props.clear()
    _cleanup_menu()
    _clear_world(true)
    world_root.process_mode = Node.PROCESS_MODE_DISABLED

    var menu := _show_menu(MAIN_MENU_SCENE)
    if menu == null:
        return
    menu.connect("start_game_requested", _on_start_game_requested)
    menu.connect("exit_requested", _on_exit_requested)


func start_new_run() -> void:
    _cleanup_menu()
    _clear_world(true)
    selected_props_by_slot.clear()
    _current_reward_props.clear()
    current_duel_index = 0
    player_instance = PLAYER_SCENE.instantiate() as Node3D
    if player_instance == null:
        push_error("Player scene root must be a Node3D.")
        show_main_menu()
        return
    world_root.add_child(player_instance)
    start_duel(current_duel_index)


func start_duel(duel_index: int) -> void:
    if not _is_valid_duel_index(duel_index):
        push_warning("Cannot start invalid duel index %d." % duel_index)
        return

    current_duel_index = duel_index
    _cleanup_menu()
    _clear_current_enemy()
    _clear_current_arena()
    if not is_instance_valid(player_instance):
        player_instance = PLAYER_SCENE.instantiate() as Node3D
        if player_instance == null:
            push_error("Player scene root must be a Node3D.")
            show_main_menu()
            return
        world_root.add_child(player_instance)

    arena_instance = ARENA_SCENE.instantiate() as Node3D
    if arena_instance == null:
        push_error("Arena scene root must be a Node3D.")
        show_main_menu()
        return
    world_root.add_child(arena_instance)

    var player_spawn := _get_spawn_transform(arena_instance, "PlayerSpawn", FALLBACK_PLAYER_SPAWN)
    var enemy_spawn := _get_spawn_transform(arena_instance, "EnemySpawn", FALLBACK_ENEMY_SPAWN)
    player_instance.global_transform = player_spawn
    player_instance.call("reset_for_duel")
    for definition in selected_props_by_slot.values():
        if definition != null:
            player_instance.call("equip_prop", definition)

    var enemy_scene: PackedScene = DUEL_CONFIG[duel_index]["enemy_scene"]
    enemy_instance = enemy_scene.instantiate() as Node3D
    if enemy_instance == null:
        push_error("Enemy scene root must be a Node3D for duel %d." % duel_index)
        show_main_menu()
        return
    world_root.add_child(enemy_instance)
    enemy_instance.global_transform = enemy_spawn

    flow_state = State.DUEL
    world_root.process_mode = Node.PROCESS_MODE_INHERIT


func show_upgrade_selection(defeated_enemy: Node) -> void:
    if flow_state != State.DUEL or defeated_enemy != enemy_instance:
        return
    if not is_instance_valid(defeated_enemy) or not defeated_enemy.has_method("get_equipped_prop_definitions"):
        push_warning("Cannot create reward choices: defeated enemy has no equipped-prop API.")
        show_main_menu()
        return

    var reward_props: Array[CharacterPropDefinition] = defeated_enemy.call("get_equipped_prop_definitions")
    var has_null_reward := false
    for definition in reward_props:
        if definition == null:
            has_null_reward = true
            break
    if reward_props.size() != 3 or has_null_reward:
        push_warning("Duel %d must provide exactly three equipped reward props; received %d." % [current_duel_index + 1, reward_props.size()])
        show_main_menu()
        return

    _current_reward_props = reward_props.duplicate()
    _clear_current_enemy()
    flow_state = State.UPGRADE_SELECTION
    world_root.process_mode = Node.PROCESS_MODE_DISABLED
    var menu := _show_menu(UPGRADE_MENU_SCENE)
    if menu == null:
        show_main_menu()
        return
    menu.connect("prop_selected", _on_prop_selected)
    menu.call("setup_choices", _current_reward_props)


func on_upgrade_selected(prop_definition: CharacterPropDefinition) -> void:
    if flow_state != State.UPGRADE_SELECTION or prop_definition == null or not _current_reward_props.has(prop_definition):
        return
    if not is_instance_valid(player_instance):
        push_warning("Cannot apply reward: the current player no longer exists.")
        show_main_menu()
        return

    selected_props_by_slot[prop_definition.slot] = prop_definition
    player_instance.call("equip_prop", prop_definition)
    _current_reward_props.clear()
    _cleanup_menu()
    current_duel_index += 1
    start_duel(current_duel_index)


func show_defeat_menu() -> void:
    if flow_state != State.DUEL:
        return
    flow_state = State.DEFEAT
    _cleanup_menu()
    world_root.process_mode = Node.PROCESS_MODE_DISABLED
    var menu := _show_menu(DEFEAT_MENU_SCENE)
    if menu == null:
        show_main_menu()
        return
    menu.connect("retry_requested", _on_retry_requested)
    menu.connect("main_menu_requested", _on_main_menu_requested)


func retry_current_duel() -> void:
    if flow_state != State.DEFEAT or not _is_valid_duel_index(current_duel_index):
        return
    start_duel(current_duel_index)


func show_victory_menu() -> void:
    if flow_state != State.DUEL:
        return
    flow_state = State.VICTORY
    _current_reward_props.clear()
    _cleanup_menu()
    world_root.process_mode = Node.PROCESS_MODE_DISABLED
    var menu := _show_menu(VICTORY_MENU_SCENE)
    if menu == null:
        show_main_menu()
        return
    menu.connect("play_again_requested", _on_play_again_requested)
    menu.connect("main_menu_requested", _on_main_menu_requested)


func return_to_main_menu() -> void:
    selected_props_by_slot.clear()
    current_duel_index = 0
    show_main_menu()


func _on_character_defeated(character: Node) -> void:
    if flow_state != State.DUEL or not is_instance_valid(character):
        return
    if character == player_instance:
        if character.has_method("is_player_character") and character.call("is_player_character"):
            call_deferred("show_defeat_menu")
        return
    if character != enemy_instance or not character.has_method("is_enemy_character") or not character.call("is_enemy_character"):
        return

    if current_duel_index == DUEL_CONFIG.size() - 1:
        call_deferred("show_victory_menu")
    else:
        call_deferred("show_upgrade_selection", character)


func _show_menu(menu_scene: PackedScene) -> Control:
    var menu := menu_scene.instantiate() as Control
    if menu == null:
        push_error("Flow menu scene root must be a Control.")
        return null
    menu.process_mode = Node.PROCESS_MODE_ALWAYS
    ui_root.add_child(menu)
    current_menu = menu
    return menu


func _cleanup_menu() -> void:
    if not is_instance_valid(current_menu):
        current_menu = null
        return

    var callbacks := {
        "start_game_requested": Callable(self, "_on_start_game_requested"),
        "exit_requested": Callable(self, "_on_exit_requested"),
        "prop_selected": Callable(self, "_on_prop_selected"),
        "retry_requested": Callable(self, "_on_retry_requested"),
        "play_again_requested": Callable(self, "_on_play_again_requested"),
        "main_menu_requested": Callable(self, "_on_main_menu_requested"),
    }
    for signal_name in callbacks:
        var callback: Callable = callbacks[signal_name]
        if current_menu.has_signal(signal_name) and current_menu.is_connected(signal_name, callback):
            current_menu.disconnect(signal_name, callback)
    current_menu.free()
    current_menu = null


func _clear_world(clear_player: bool) -> void:
    _clear_current_enemy()
    _clear_current_arena()
    if clear_player and is_instance_valid(player_instance):
        player_instance.free()
        player_instance = null


func _clear_current_enemy() -> void:
    if is_instance_valid(enemy_instance):
        enemy_instance.free()
    enemy_instance = null


func _clear_current_arena() -> void:
    if is_instance_valid(arena_instance):
        arena_instance.free()
    arena_instance = null


func _get_spawn_transform(arena: Node3D, marker_name: String, fallback_position: Vector3) -> Transform3D:
    var marker := arena.get_node_or_null(marker_name) as Marker3D
    if marker != null:
        return marker.global_transform

    push_warning("Arena is missing %s; using fallback spawn position %s." % [marker_name, fallback_position])
    return arena.global_transform * Transform3D(Basis.IDENTITY, fallback_position)


func _is_valid_duel_index(duel_index: int) -> bool:
    return duel_index >= 0 and duel_index < DUEL_CONFIG.size()


func _on_start_game_requested() -> void:
    if flow_state == State.MAIN_MENU:
        call_deferred("start_new_run")


func _on_exit_requested() -> void:
    if flow_state == State.MAIN_MENU:
        call_deferred("_quit_application")


func _on_prop_selected(prop_definition: CharacterPropDefinition) -> void:
    call_deferred("on_upgrade_selected", prop_definition)


func _on_retry_requested() -> void:
    if flow_state == State.DEFEAT:
        call_deferred("retry_current_duel")


func _on_play_again_requested() -> void:
    if flow_state == State.VICTORY:
        call_deferred("start_new_run")


func _on_main_menu_requested() -> void:
    if flow_state == State.DEFEAT or flow_state == State.VICTORY:
        call_deferred("return_to_main_menu")


func _quit_application() -> void:
    get_tree().quit()
