extends Area2D

@onready var sfx: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		sfx.play()
		
		# Hide coin immediately
		visible = false
		set_deferred("monitoring", false)

		# Wait for sound to finish, then delete
		await sfx.finished
		queue_free()
