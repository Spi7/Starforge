extends CanvasLayer

var economy: SessionEconomy

@onready var credits_label: Label = $Resources/Credits


func bind_economy(state: SessionEconomy) -> void:
	economy = state
	economy.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	credits_label.text = "Credits: %d C" % economy.credits
