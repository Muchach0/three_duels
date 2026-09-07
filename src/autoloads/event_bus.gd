extends Node


signal ui_color_button
signal ui_model_button
signal ui_sword_button
signal ui_left_hand_button
signal ui_helmet_button
signal ui_left_shoulder_button
signal ui_right_shoulder_button
signal ui_exit_button

signal ui_test_sword_enable_collision
signal ui_test_enemy_attack
signal ui_test_enemy_block
signal ui_test_enemy_idle
signal ui_test_enemy_clear_override


signal combat_hit_detected(attacker: Node, defender: Node, hit_data: Dictionary)
signal combat_damage_applied(defender: Node, hit_data: Dictionary)
signal combat_stats_changed(character: Node, health: float, max_health: float, guard: float, max_guard: float)
signal combat_character_defeated(character: Node)


signal player_attacking
signal enemy_attacking
