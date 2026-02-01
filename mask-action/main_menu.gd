extends Control

@onready var fade: ColorRect = $Fade
const GAME_SCENE := "res://Scenes/main.tscn"

func _ready() -> void:
	fade.modulate.a = 1.0
	create_tween().tween_property(fade, "modulate:a", 0.0, 0.6)

func _on_start_button_pressed() -> void:
	# Fade to black
	var t := create_tween()
	t.tween_property(fade, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		get_tree().change_scene_to_file(GAME_SCENE)
	)
