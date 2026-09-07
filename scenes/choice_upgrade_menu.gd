extends Control


signal prop_selected(prop_definition: CharacterPropDefinition)


@onready var cards: Array[Button] = [
	$MarginContainer/HBoxContainer/Card1,
	$MarginContainer/HBoxContainer/Card2,
	$MarginContainer/HBoxContainer/Card3,
]
@onready var card_labels: Array[Label] = [
	$MarginContainer/HBoxContainer/Card1/MarginContainer/VBoxContainer/Label,
	$MarginContainer/HBoxContainer/Card2/MarginContainer/VBoxContainer/Label,
	$MarginContainer/HBoxContainer/Card3/MarginContainer/VBoxContainer/Label,
]
@onready var card_icons: Array[TextureRect] = [
	$MarginContainer/HBoxContainer/Card1/MarginContainer/VBoxContainer/TextureRect,
	$MarginContainer/HBoxContainer/Card2/MarginContainer/VBoxContainer/TextureRect,
	$MarginContainer/HBoxContainer/Card3/MarginContainer/VBoxContainer/TextureRect,
]

var _choices: Array[CharacterPropDefinition] = []
var _selection_made := false


func _ready() -> void:
	for index in cards.size():
		if not cards[index].pressed.is_connected(_on_card_pressed.bind(index)):
			cards[index].pressed.connect(_on_card_pressed.bind(index))


func setup_choices(props: Array[CharacterPropDefinition]) -> void:
	if props.size() != cards.size():
		push_warning("Upgrade menu requires exactly three prop choices; received %d." % props.size())
		return

	_choices = props.duplicate()
	_selection_made = false
	$Three_Column_Control.visible = false
	$MarginContainer.visible = true
	for index in cards.size():
		var definition := _choices[index]
		cards[index].disabled = definition == null
		card_labels[index].text = "" if definition == null else definition.display_name
		card_icons[index].texture = null
		card_icons[index].visible = false
		if index == 0:
			cards[index].grab_focus()


func _on_card_pressed(index: int) -> void:
	if _selection_made or index < 0 or index >= _choices.size():
		return

	var definition := _choices[index]
	if definition == null:
		return

	_selection_made = true
	for card in cards:
		card.disabled = true
	prop_selected.emit(definition)
