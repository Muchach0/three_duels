extends Control


signal prop_selected(prop_definition: CharacterPropDefinition)


@onready var cards: Array[Button] = [
    $MarginContainer/VBoxContainer/HBoxContainer/Card1,
    $MarginContainer/VBoxContainer/HBoxContainer/Card2,
    $MarginContainer/VBoxContainer/HBoxContainer/Card3,
]
@onready var card_labels: Array[Label] = [
    $MarginContainer/VBoxContainer/HBoxContainer/Card1/MarginContainer/VBoxContainer/Label,
    $MarginContainer/VBoxContainer/HBoxContainer/Card2/MarginContainer/VBoxContainer/Label,
    $MarginContainer/VBoxContainer/HBoxContainer/Card3/MarginContainer/VBoxContainer/Label,
]
@onready var card_icons: Array[TextureRect] = [
    $MarginContainer/VBoxContainer/HBoxContainer/Card1/MarginContainer/VBoxContainer/TextureRect,
    $MarginContainer/VBoxContainer/HBoxContainer/Card2/MarginContainer/VBoxContainer/TextureRect,
    $MarginContainer/VBoxContainer/HBoxContainer/Card3/MarginContainer/VBoxContainer/TextureRect,
]
@onready var validate_button: Button = $MarginContainer/VBoxContainer/Button

var _choices: Array[CharacterPropDefinition] = []
var _selected_index := -1
var _selection_made := false


func _ready() -> void:
    validate_button.pressed.connect(_on_validate_pressed)
    for index in cards.size():
        cards[index].disabled = true
        if not cards[index].pressed.is_connected(_on_card_pressed.bind(index)):
            cards[index].pressed.connect(_on_card_pressed.bind(index))


func setup_choices(props: Array[CharacterPropDefinition]) -> void:
    if props.size() != cards.size():
        push_warning("Upgrade menu requires exactly three prop choices; received %d." % props.size())
        return

    _choices = props.duplicate()
    _selected_index = -1
    _selection_made = false
    validate_button.disabled = true
    $Three_Column_Control.visible = false
    $MarginContainer.visible = true
    for index in cards.size():
        var definition := _choices[index]
        cards[index].set_pressed_no_signal(false)
        cards[index].disabled = definition == null
        card_labels[index].text = "" if definition == null else definition.display_name
        card_icons[index].texture = null
        card_icons[index].visible = false
    for card in cards:
        if not card.disabled:
            card.grab_focus()
            break


func _on_card_pressed(index: int) -> void:
    if _selection_made or index < 0 or index >= _choices.size():
        return

    if _choices[index] == null:
        return

    _selected_index = index
    validate_button.disabled = false


func _on_validate_pressed() -> void:
    if _selection_made or _selected_index < 0 or _selected_index >= _choices.size():
        return

    var definition := _choices[_selected_index]
    if definition == null:
        return

    _selection_made = true
    validate_button.disabled = true
    for card in cards:
        card.disabled = true
    prop_selected.emit(definition)
