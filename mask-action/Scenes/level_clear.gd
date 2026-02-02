extends Control

@onready var fade: ColorRect = $Fade
const MAIN_MENU_SCENE := "res://Scenes/main_menu.tscn"

func _ready() -> void:
	# Fade in
	if fade:
		fade.modulate.a = 1.0
		create_tween().tween_property(fade, "modulate:a", 0.0, 0.6)

func _on_restart_game_button_pressed() -> void:
	# Fade out then return to main menu
	if fade:
		var t := create_tween()
		t.tween_property(fade, "modulate:a", 1.0, 0.35)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN)
		t.tween_callback(func():
			get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		)
	else:
		# No fade fallback
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
