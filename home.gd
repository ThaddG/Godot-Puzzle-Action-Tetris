extends Control

func _ready():
	$PlayButton.pressed.connect(_on_play_pressed)
	$SettingsButton.pressed.connect(_on_settings_pressed)

func _on_play_pressed():
	get_tree().change_scene_to_file("res://main.tscn")

func _on_settings_pressed():
	get_tree().change_scene_to_file("res://settings.tscn")
