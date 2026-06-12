extends Control

var _cards: Array[PanelContainer] = []


func _ready() -> void:
	for index in range(12):
		var node: Node = find_child("Tile%02d" % index, true, false)
		if node is PanelContainer:
			var card: PanelContainer = node
			_cards.append(card)


func _process(_delta: float) -> void:
	for index in range(_cards.size()):
		var card: PanelContainer = _cards[index]
		card.pivot_offset = card.size * 0.5
		card.rotation = sin(Time.get_ticks_msec() * 0.0014 + float(index) * 0.37) * 0.018
