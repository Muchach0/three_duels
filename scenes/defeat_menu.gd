extends Control


signal retry_requested
signal main_menu_requested


@onready var retry_button: Button = $Control/VBoxContainer/RetryButton
@onready var main_menu_button: Button = $Control/VBoxContainer/MainMenuButton


func _ready() -> void:
	if not retry_button.pressed.is_connected(_on_retry_button_pressed):
		retry_button.pressed.connect(_on_retry_button_pressed)
	if not main_menu_button.pressed.is_connected(_on_main_menu_button_pressed):
		main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	retry_button.grab_focus()


func _on_retry_button_pressed() -> void:
	retry_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
