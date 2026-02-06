extends Control

var settings

func _ready():
	settings = get_node("/root/GameSettings")
	$BackButton.pressed.connect(_on_back_pressed)
	%GhostPieceToggle.toggled.connect(_on_ghost_toggle)
	
	# Set toggle to match current setting
	%GhostPieceToggle.button_pressed = settings.ghost_piece_enabled

func _on_back_pressed():
	get_tree().change_scene_to_file("res://home.tscn")

func _on_ghost_toggle(enabled: bool):
	settings.ghost_piece_enabled = enabled
