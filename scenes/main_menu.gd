extends Control


signal start_game_requested
signal exit_requested


@onready var start_button: Button = $Button_Control/VBoxContainer/Button
@onready var exit_button: Button = $Button_Control/VBoxContainer/Button2


func _ready() -> void:
    if not start_button.pressed.is_connected(_on_start_button_pressed):
        start_button.pressed.connect(_on_start_button_pressed)
    if not exit_button.pressed.is_connected(_on_exit_button_pressed):
        exit_button.pressed.connect(_on_exit_button_pressed)
    start_button.grab_focus()


func _on_start_button_pressed() -> void:
    start_game_requested.emit()


func _on_exit_button_pressed() -> void:
    exit_requested.emit()
