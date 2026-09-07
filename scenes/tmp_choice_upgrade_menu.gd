extends Control

signal upgrade_chosen(choice_id: int)

const UpgradeChoiceBuilderScript = preload("res://resources/upgrades/upgrade_choice_builder.gd")

# Upgrades available and that will be choosen randomly
# @export var upgrade_availables: Array[Resource] = []

# ordered list of available upgrades for the player to choose from
@onready var upgrades_choosen_randomly_list: Array[Upgrade] = []

@onready var upgrade_buttons: Array[Button] = [
    $MarginContainer/HBoxContainer/Card1,
    $MarginContainer/HBoxContainer/Card2,
    $MarginContainer/HBoxContainer/Card3,
]

var upgrade_context: Dictionary = {}
var _unavailable_label: Label = null


func _ready() -> void:
    upgrades_choosen_randomly_list.clear()
    upgrades_choosen_randomly_list = UpgradeChoiceBuilderScript.build_choices(upgrade_buttons.size(), upgrade_context)

    for index in upgrade_buttons.size():
        var button := upgrade_buttons[index]
        _clear_button(button)

        if index >= upgrades_choosen_randomly_list.size():
            button.hide()
            button.disabled = true
            continue

        var upgrade_choosen_randomly := upgrades_choosen_randomly_list[index]
        var icon: TextureRect = button.get_node("MarginContainer/VBoxContainer/TextureRect")
        var label: Label = button.get_node("MarginContainer/VBoxContainer/Label")
        icon.texture = upgrade_choosen_randomly.get_icon()
        label.text = upgrade_choosen_randomly.get_upgrade_name() + "\n" + upgrade_choosen_randomly.get_description()

        button.show()
        button.disabled = false
        button.pressed.connect(_on_upgrade_button_pressed.bind(index))

    if upgrades_choosen_randomly_list.is_empty():
        _show_unavailable_label()
    elif _unavailable_label != null:
        _unavailable_label.hide()


func _on_upgrade_button_pressed(choice_id: int) -> void:
    if choice_id < 0 or choice_id >= upgrades_choosen_randomly_list.size():
        push_warning("ChoiceUpgradeMenu: Invalid upgrade choice index: %s" % choice_id)
        return

    EventBus.upgrade_chosen.emit(upgrades_choosen_randomly_list[choice_id])


func _clear_button(button: Button) -> void:
    var icon: TextureRect = button.get_node("MarginContainer/VBoxContainer/TextureRect")
    var label: Label = button.get_node("MarginContainer/VBoxContainer/Label")
    icon.texture = null
    label.text = ""

    for connection: Dictionary in button.pressed.get_connections():
        button.pressed.disconnect(connection["callable"])


func _show_unavailable_label() -> void:
    if _unavailable_label == null:
        _unavailable_label = Label.new()
        _unavailable_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _unavailable_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        _unavailable_label.text = "No upgrades available"
        add_child(_unavailable_label)
        _unavailable_label.set_anchors_preset(Control.PRESET_FULL_RECT)

    _unavailable_label.show()
