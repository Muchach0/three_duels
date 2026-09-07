extends Control


signal play_again_requested
signal main_menu_requested


@onready var play_again_button: Button = $Control/VBoxContainer/RetryButton
@onready var main_menu_button: Button = $Control/VBoxContainer/MainMenuButton


func _ready() -> void:
	if not play_again_button.pressed.is_connected(_on_play_again_button_pressed):
		play_again_button.pressed.connect(_on_play_again_button_pressed)
	if not main_menu_button.pressed.is_connected(_on_main_menu_button_pressed):
		main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	play_again_button.grab_focus()


func _on_play_again_button_pressed() -> void:
	play_again_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
